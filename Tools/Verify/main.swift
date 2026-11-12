import Foundation
import VeylumeKit

let result = await NativeVerification.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(result)
