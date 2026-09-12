import AntiFishCore
import Foundation

let usage = """
antifish \(AntiFishCore.version) — flags WhatsApp voice notes whose voice does not match the sender

usage: antifish [--db <path> | --memory-db] [--models <dir>] <command>

  status                 container, permissions, counts, thresholds
  enroll                 build voice fingerprints from the notes on this Mac, then calibrate
  verify [--newest [n]]  verify the newest n incoming notes (default 1)
  verify <path|id>       verify one note by media path or message id
  calibrate              recompute thresholds from the stored enrolment
  feed [n]               print the last n verdicts
  images [n]             read the words inside recent pictures, locally
"""

do {
    let options = try CLIOptions.parse(CommandLine.arguments)
    try await CLI(options: options).run()
} catch CLIError.usage {
    print(usage)
    exit(1)
} catch CLIError.whatsAppUnavailable(let why) {
    FileHandle.standardError.write(Data("error: \(why)\n".utf8))
    exit(2)
} catch CLIError.modelsMissing(let dir) {
    FileHandle.standardError.write(Data("error: models missing in \(dir); run `make models`\n".utf8))
    exit(3)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
