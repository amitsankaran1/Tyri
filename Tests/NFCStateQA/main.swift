import Foundation
protocol NFCTagReaderSessionDelegate {}
struct Tag {var identifier=Data([1,2]);var currentIDm=Data([1,2])}
enum NFCTag {case iso7816(Tag),feliCa(Tag),iso15693(Tag),miFare(Tag)}
class NFCTagReaderSession {
 enum Polling {case iso14443}
 static var readingAvailable=true
 static var created:[NFCTagReaderSession]=[]
 var alertMessage="";var completion:((Error?)->Void)?
 init(pollingOption:Polling,delegate:NFCTagReaderSessionDelegate,queue:DispatchQueue?){Self.created.append(self)}
 func begin(){};func invalidate(){};func invalidate(errorMessage:String){}
 func connect(to tag:NFCTag,completionHandler:@escaping (Error?)->Void){completion=completionHandler}
}
struct NFCReaderError:Error {enum Code{case readerSessionInvalidationErrorUserCanceled,readerSessionInvalidationErrorSessionTimeout,other};var code:Code;var localizedDescription:String{"test"}}
enum SharedDefaults {static let suite=UserDefaults(suiteName:"tyri-nfc-\(UUID())")!}
@MainActor class AppConfigurationStore {static let shared=AppConfigurationStore();var registeredTagIdentifier:String?;func registerTag(identifier:String){registeredTagIdentifier=identifier}}
struct BlockRule {enum Kind{case tag};var id=UUID();var isEnabled=false}
@MainActor class BlockStore {static let shared=BlockStore();func blocks(ofType:BlockRule.Kind)->[BlockRule]{[]};func setEnabled(id:UUID,enabled:Bool){};func flush(){}}
@MainActor class ScreenTimeManager {static let shared=ScreenTimeManager();func clearBlockShield(id:UUID){};func applyBlockShield(_ b:BlockRule){}}
enum BreakMonitoring {static func resetAllowance(blockID:UUID){}}
@main struct Tests {
 @MainActor static func main() async {
  let nfc=NFCManager.shared;var count=0,failures=0;nfc.onTagScanned={_ in count+=1}
  func check(_ yes:Bool,_ name:String){print("\(yes ? "PASS":"FAIL"): \(name)");if !yes{failures+=1}}
  nfc.startScanning();let first=NFCTagReaderSession.created.last!
  nfc.startScanning();check(NFCTagReaderSession.created.last === first,"SM-04 repeated Start retains one scan")
  nfc.stopScanning();nfc.startScanning();let second=NFCTagReaderSession.created.last!
  nfc.tagReaderSession(first,didInvalidateWithError:NFCReaderError(code:.readerSessionInvalidationErrorSessionTimeout))
  for _ in 0..<5 {await Task.yield()}
  check(nfc.isScanning && nfc.errorMessage == nil,"SM-04 old invalidation cannot cancel or error a newer scan")
  nfc.tagReaderSession(second,didDetect:[.miFare(Tag())]);second.completion?(nil);second.completion?(nil)
  for _ in 0..<5 {await Task.yield()}
  check(count==1,"SM-04 duplicate completion toggles exactly once")
  nfc.startScanning();let third=NFCTagReaderSession.created.last!
  nfc.tagReaderSession(third,didDetect:[.miFare(Tag())]);nfc.stopScanning();third.completion?(nil)
  for _ in 0..<5 {await Task.yield()}
  check(count==1,"SM-04 canceled reader ignores delayed connection completion")
  if failures>0 {exit(1)}
 }
}
