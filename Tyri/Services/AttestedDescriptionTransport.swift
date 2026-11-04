import Foundation
import DeviceCheck
import CryptoKit

/// Serializes proof generation so App Attest counters cannot race across requests.
@MainActor
final class AttestedDescriptionTransport {
    static let shared = AttestedDescriptionTransport()
    private let service = DCAppAttestService.shared
    private let defaults = UserDefaults.standard
    private var inFlight = false
    private let keyStorage = "tyri.description.attest.key.v2"
    private let enrollmentStorage = "tyri.description.attest.enrolled.v2"
    private let pendingStorage = "tyri.description.attest.pending.v2"
    private struct Challenge: Decodable { let id: String; let challenge: String }
    private struct Enrollment: Codable { let keyID: String; let challengeID: String; let attestation: String }
    private struct ChallengeRequest: Encodable { let keyID: String; let purpose: String }
    private struct SignedRequest: Encodable { let challengeID: String; let challenge: String; let request: DescriptionRequest }
    private struct ServiceFailure: Decodable { let error: String }
    private struct RemoteError: Error { let code: String; let status: Int }

    func interpret(_ request: DescriptionRequest) async throws -> BlockDescriptionDraft {
        guard !inFlight else { throw DescriptionError.message("Another description is still being processed. Please wait.") }
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "TyriDescriptionEndpoint") as? String,
              let endpoint = URL(string: raw), endpoint.scheme == "https", endpoint.host != nil else {
            throw DescriptionError.message("Natural-language interpretation isn't connected in this build yet. Use the manual block options in Focus.")
        }
        guard service.isSupported else {
            throw DescriptionError.message("Device verification isn't available here. Natural-language blocks require a supported physical device; you can still use the manual block editor.")
        }
        inFlight = true; defer { inFlight = false }
        do {
            let key = try await prepareKey(endpoint)
            try Task.checkCancellation()
            let challenge: Challenge = try await send(ChallengeRequest(keyID:key,purpose:"create"), to:endpoint, path:"challenge")
            let bytes = try encode(SignedRequest(challengeID:challenge.id,challenge:challenge.challenge,request:request))
            let proof = try await service.generateAssertion(key, clientDataHash: Data(SHA256.hash(data:bytes)))
            try Task.checkCancellation()
            let response = try await post(bytes, to:endpoint, path:"create", headers:["x-tyri-key-id":key,"x-tyri-assertion":proof.base64EncodedString()])
            return try JSONDecoder().decode(BlockDescriptionDraft.self,from:response)
        } catch let error as RemoteError {
            if error.code == "device_not_enrolled" || error.code == "device_verification_failed" {
                // Lost server enrollment (e.g. backend restoration) needs a fresh hardware key.
                resetKey()
            }
            switch error.code {
            case "provider_unconfigured": throw DescriptionError.message("The interpretation service is being configured. Your description is preserved; use the manual editor for now.")
            case "rate_limited": throw DescriptionError.message("The interpretation service has reached its request limit. Try later or use the manual editor.")
            case "device_not_enrolled", "device_verification_failed": throw DescriptionError.message("Device verification needs to be renewed. Your description is preserved. Try again to register this device.")
            default: throw DescriptionError.message("The interpretation service is unavailable. Your description is preserved. Try again later or use the manual editor.")
            }
        } catch {
            let native = error as NSError
            if native.domain == DCError.errorDomain && native.code == DCError.invalidKey.rawValue {
                resetKey()
                throw DescriptionError.message("The device verification key is no longer valid. Try again to register this device.")
            }
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            if let known = error as? DescriptionError { throw known }
            throw DescriptionError.message("Could not complete device verification or contact the service. Your description is preserved; please try again.")
        }
    }
    private func prepareKey(_ endpoint: URL) async throws -> String {
        let key: String
        if let saved = defaults.string(forKey:keyStorage) { key = saved }
        else { key = try await service.generateKey(); defaults.set(key,forKey:keyStorage) }
        if defaults.string(forKey:enrollmentStorage) == key { return key }
        let payload: Data
        if let pending = defaults.data(forKey:pendingStorage), let decoded = try? JSONDecoder().decode(Enrollment.self,from:pending), decoded.keyID == key {
            payload = pending
        } else {
            let challenge: Challenge = try await send(ChallengeRequest(keyID:key,purpose:"enroll"), to:endpoint, path:"challenge")
            guard let nonce = Data(base64Encoded:challenge.challenge), nonce.count == 32 else { throw DescriptionError.invalid }
            let attestation = try await service.attestKey(key,clientDataHash:Data(SHA256.hash(data:nonce)))
            payload = try encode(Enrollment(keyID:key,challengeID:challenge.id,attestation:attestation.base64EncodedString()))
            // Keep exact bytes: retrying a lost response must not reorder enrollment fields.
            defaults.set(payload,forKey:pendingStorage)
        }
        _ = try await post(payload,to:endpoint,path:"enroll")
        defaults.set(key,forKey:enrollmentStorage)
        defaults.removeObject(forKey:pendingStorage)
        return key
    }
    private func resetKey() {
        for key in [keyStorage,enrollmentStorage,pendingStorage] { defaults.removeObject(forKey:key) }
    }
    private func encode<T: Encodable>(_ value:T) throws -> Data { let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys];return try encoder.encode(value) }
    private func send<T:Encodable,R:Decodable>(_ value:T,to endpoint:URL,path:String) async throws -> R {
        try await JSONDecoder().decode(R.self,from:post(encode(value),to:endpoint,path:path))
    }
    private func post(_ bytes:Data,to endpoint:URL,path:String,headers:[String:String]=[:]) async throws -> Data {
        var request=URLRequest(url:endpoint.appendingPathComponent("api").appendingPathComponent(path))
        request.httpMethod="POST"; request.httpBody=bytes;request.timeoutInterval=45
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        headers.forEach { request.setValue($0.value,forHTTPHeaderField:$0.key) }
        let (data,response)=try await URLSession.shared.data(for:request)
        guard let http=response as? HTTPURLResponse, data.count <= 65536 else { throw DescriptionError.invalid }
        guard http.statusCode == 200 else {
            throw RemoteError(code:(try? JSONDecoder().decode(ServiceFailure.self,from:data).error) ?? "service_unavailable",status:http.statusCode)
        }
        return data
    }
}
