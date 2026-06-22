import Foundation

struct BackendErrorResponse: Decodable {
    let error: String?
    let message: String?
}
