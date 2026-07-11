import Foundation

struct BackendErrorResponse: Decodable {
    let error: String?
    let message: String?
    let retry_after_seconds: Int?
}
