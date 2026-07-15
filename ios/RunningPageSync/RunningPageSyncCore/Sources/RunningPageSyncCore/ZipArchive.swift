import Foundation

public struct ZipEntry: Equatable, Sendable {
    public let name: String
    public let data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

public struct ZipArchiveBuilder: Sendable {
    public init() {}

    public func archive(entries: [ZipEntry]) throws -> Data {
        guard entries.count <= Int(UInt16.max) else {
            throw WorkoutSyncError.archiveTooLarge
        }

        var archive = Data()
        var centralDirectory = Data()

        for entry in entries {
            let name = try validatedName(entry.name)
            let nameData = Data(name.utf8)
            guard nameData.count <= Int(UInt16.max),
                  entry.data.count <= Int(UInt32.max),
                  archive.count <= Int(UInt32.max) else {
                throw WorkoutSyncError.archiveTooLarge
            }

            let checksum = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)
            let localHeaderOffset = UInt32(archive.count)

            archive.appendLittleEndian(UInt32(0x04034b50))
            archive.appendLittleEndian(UInt16(20))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(UInt16(0))
            archive.appendLittleEndian(checksum)
            archive.appendLittleEndian(size)
            archive.appendLittleEndian(size)
            archive.appendLittleEndian(UInt16(nameData.count))
            archive.appendLittleEndian(UInt16(0))
            archive.append(nameData)
            archive.append(entry.data)

            centralDirectory.appendLittleEndian(UInt32(0x02014b50))
            centralDirectory.appendLittleEndian(UInt16(20))
            centralDirectory.appendLittleEndian(UInt16(20))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(checksum)
            centralDirectory.appendLittleEndian(size)
            centralDirectory.appendLittleEndian(size)
            centralDirectory.appendLittleEndian(UInt16(nameData.count))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt16(0))
            centralDirectory.appendLittleEndian(UInt32(0))
            centralDirectory.appendLittleEndian(localHeaderOffset)
            centralDirectory.append(nameData)
        }

        guard archive.count <= Int(UInt32.max),
              centralDirectory.count <= Int(UInt32.max),
              archive.count + centralDirectory.count <= Int(UInt32.max) else {
            throw WorkoutSyncError.archiveTooLarge
        }

        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        archive.appendLittleEndian(UInt32(0x06054b50))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(0))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(UInt32(centralDirectory.count))
        archive.appendLittleEndian(centralDirectoryOffset)
        archive.appendLittleEndian(UInt16(0))
        return archive
    }

    private func validatedName(_ name: String) throws -> String {
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        guard !name.isEmpty,
              !name.hasPrefix("/"),
              name.lowercased().hasSuffix(".gpx"),
              !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw WorkoutSyncError.invalidArchiveEntry
        }
        return name
    }
}

private enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var value = UInt32.max
        for byte in data {
            value ^= UInt32(byte)
            for _ in 0..<8 {
                value = (value >> 1) ^ (0xedb88320 & (0 &- (value & 1)))
            }
        }
        return value ^ UInt32.max
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
