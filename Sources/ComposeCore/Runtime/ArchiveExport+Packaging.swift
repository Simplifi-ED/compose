import ContainerizationArchive
import Foundation

extension ArchiveExport {
    package static func writeStackArchive(
        manifestData: Data,
        composeData: Data,
        imagesTarURL: URL,
        outputURL: URL
    ) throws {
        let writer = try ArchiveWriter(
            format: .paxRestricted,
            filter: .none,
            file: outputURL
        )
        defer { try? writer.finishEncoding() }

        try writeDataEntry(
            writer: writer,
            path: ComposeArchiveFormat.manifestPath,
            data: manifestData
        )
        try writeDataEntry(
            writer: writer,
            path: ComposeArchiveFormat.composeYAMLPath,
            data: composeData
        )
        try writeFileEntry(
            writer: writer,
            path: ComposeArchiveFormat.imagesTarPath,
            fileURL: imagesTarURL
        )
    }

    private static func writeDataEntry(
        writer: ArchiveWriter,
        path: String,
        data: Data
    ) throws {
        let entry = WriteEntry()
        entry.path = path
        entry.size = Int64(data.count)
        entry.fileType = .regular
        entry.permissions = 0o644
        try writer.writeEntry(entry: entry, data: data)
    }

    private static func writeFileEntry(
        writer: ArchiveWriter,
        path: String,
        fileURL: URL
    ) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        let entry = WriteEntry()
        entry.path = path
        entry.size = fileSize
        entry.fileType = .regular
        entry.permissions = 0o644

        let fileDescriptor = open(fileURL.path, O_RDONLY)
        guard fileDescriptor >= 0 else {
            throw ComposeError.archiveWriteFailed(
                path: fileURL.path,
                underlying: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
            )
        }
        defer { close(fileDescriptor) }

        let transaction = writer.makeTransactionWriter()
        try transaction.writeHeader(entry: entry)
        let chunkSize = 4 * 1024 * 1024
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: chunkSize, alignment: 1)
        defer { buffer.deallocate() }
        guard let baseAddress = buffer.baseAddress else {
            throw ComposeError.archiveWriteFailed(
                path: fileURL.path,
                underlying: POSIXError(.EINVAL)
            )
        }
        while true {
            let bytesRead = read(fileDescriptor, baseAddress, chunkSize)
            if bytesRead == 0 { break }
            if bytesRead < 0 {
                throw ComposeError.archiveWriteFailed(
                    path: fileURL.path,
                    underlying: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                )
            }
            try transaction.writeChunk(
                data: UnsafeRawBufferPointer(start: baseAddress, count: bytesRead)
            )
        }
        try transaction.finish()
    }
}
