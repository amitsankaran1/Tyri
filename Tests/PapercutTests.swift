import Foundation

@main struct PapercutTests {
    static func main() {
        let valid = ["example.com": "example.com", " HTTPS://www.Example.com/path?q=1#top ": "example.com", "example.com?foo=bar": "example.com", "example.com:443/path": "example.com", "sub.example.co.uk": "sub.example.co.uk"]
        for (input, expected) in valid { precondition(WebsiteDomain.normalize(input) == expected, input) }
        for input in ["", "localhost", "user@example.com", "https://user:pass@example.com", "example..com", "-example.com", "example-.com", "example.com.", "exa mple.com", "ftp://example.com", "example.com:99999", "127.0.0.1", "example_com.org"] {
            precondition(WebsiteDomain.normalize(input) == nil, input)
        }
        let now = Date()
        let end = now.addingTimeInterval(3600)
        precondition(BlockingEndDescription.detail(timedEnd: end, manual: false, tag: false, now: now).hasPrefix("Unblocks at "))
        let mixed = BlockingEndDescription.detail(timedEnd: end, manual: true, tag: false, now: now)
        precondition(mixed.contains("Timed block ends at ") && mixed.contains("Block now stays on"))
        precondition(!mixed.contains("Unblocks at"))
        precondition(BlockingEndDescription.detail(timedEnd: nil, manual: true, tag: false).contains("Block now is on"))
        precondition(BlockingEndDescription.detail(timedEnd: nil, manual: true, tag: true).contains("scan your tag"))
        precondition(BlockingEndDescription.detail(timedEnd: now.addingTimeInterval(-1), manual: false, tag: false, now: now).contains("Checking"))
        print("25 papercut checks passed")
    }
}
