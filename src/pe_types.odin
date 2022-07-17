package main

PEFileHeader :: struct #packed {
	Magic:                [4]u8,
	Machine:              u16,
	NumberOfSections:     u16,
	TimeDateStamp:        u32,
	PointerToSymbolTable: u32,
	NumberOfSymbols:      u32,
	SizeOfOptionalHeader: u16,
	Characteristics:      IMAGE_FILE_SET,
}

DataDirectory :: struct #packed {
	VirtualAddress: u32,
	Size:           u32,
}

OptionalHeader32 :: struct #packed {
	Magic:                       u16,
	MajorLinkerVersion:          u8,
	MinorLinkerVersion:          u8,
	SizeOfCode:                  u32,
	SizeOfInitializedData:       u32,
	SizeOfUninitializedData:     u32,
	AddressOfEntryPoint:         u32,
	BaseOfCode:                  u32,
	BaseOfData:                  u32,
	ImageBase:                   u32,
	SectionAlignment:            u32,
	FileAlignment:               u32,
	MajorOperatingSystemVersion: u16,
	MinorOperatingSystemVersion: u16,
	MajorImageVersion:           u16,
	MinorImageVersion:           u16,
	MajorSubsystemVersion:       u16,
	MinorSubsystemVersion:       u16,
	Win32VersionValue:           u32,
	SizeOfImage:                 u32,
	SizeOfHeaders:               u32,
	CheckSum:                    u32,
	Subsystem:                   IMAGE_SUBSYSTEM,
	DllCharacteristics:          IMAGE_DLLCHARACTERISTICS,
	SizeOfStackReserve:          u32,
	SizeOfStackCommit:           u32,
	SizeOfHeapReserve:           u32,
	SizeOfHeapCommit:            u32,
	LoaderFlags:                 u32,
	NumberOfRvaAndSizes:         u32,
	DataDirectory: [16]DataDirectory,
}

OptionalHeader64 :: struct #packed {
	Magic:                       u16,
	MajorLinkerVersion:          u8,
	MinorLinkerVersion:          u8,
	SizeOfCode:                  u32,
	SizeOfInitializedData:       u32,
	SizeOfUninitializedData:     u32,
	AddressOfEntryPoint:         u32,
	BaseOfCode:                  u32,
	ImageBase:                   u64,
	SectionAlignment:            u32,
	FileAlignment:               u32,
	MajorOperatingSystemVersion: u16,
	MinorOperatingSystemVersion: u16,
	MajorImageVersion:           u16,
	MinorImageVersion:           u16,
	MajorSubsystemVersion:       u16,
	MinorSubsystemVersion:       u16,
	Win32VersionValue:           u32,
	SizeOfImage:                 u32,
	SizeOfHeaders:               u32,
	CheckSum:                    u32,
	Subsystem:                   IMAGE_SUBSYSTEM,
	DllCharacteristics:          IMAGE_DLLCHARACTERISTICS,
	SizeOfStackReserve:          u64,
	SizeOfStackCommit:           u64,
	SizeOfHeapReserve:           u64,
	SizeOfHeapCommit:            u64,
	LoaderFlags:                 u32,
	NumberOfRvaAndSizes:         u32,
	DataDirectory: [16]DataDirectory,
}

SectionHeader32 :: struct #packed {
	Name:                 [8]u8,
	VirtualSize:          u32,
	VirtualAddress:       u32,
	SizeOfRawData:        u32,
	PointerToRawData:     u32,
	PointerToRelocations: u32,
	PointerToLineNumbers: u32,
	NumberOfRelocations:  u16,
	NumberOfLineNumbers:  u16,
	Characteristics:      u32,
}


IMAGE_FILE_MACHINE_I386  :: 0x014c
IMAGE_FILE_MACHINE_AMD64 :: 0x8664

// characteristics
IMAGE_FILE_SET :: distinct bit_set[IMAGE_FILE; u16]
IMAGE_FILE :: enum u16 {
	RELOCS_STRIPPED         = 0,
	EXECUTABLE_IMAGE        = 1,
	LINE_NUMS_STRIPPED      = 2,
	LOCAL_SYMS_STRIPPED     = 3,
	AGGRESIVE_WS_TRIM       = 4,
	LARGE_ADDRESS_AWARE     = 5,
	BYTES_REVERSED_LO       = 6,
	BIT32_MACHINE           = 7,
	DEBUG_STRIPPED          = 8,
	REMOVABLE_RUN_FROM_SWAP = 9,
	NET_RUN_FROM_SWAP       = 10,
	SYSTEM                  = 11,
	DLL                     = 12,
	UP_SYSTEM_ONLY          = 13,
	BYTES_REVERSED_HI       = 14,
}

IMAGE_SUBSYSTEM :: enum u16 {
	UNKNOWN                  =  0,
	NATIVE                   =  1,
	WINDOWS_GUI              =  2,
	WINDOWS_CUI              =  3,
	OS2_CUI                  =  5,
	POSIX_CUI                =  7,
	NATIVE_WINDOWS           =  8,
	WINDOWS_CE_GUI           =  9,
	EFI_APPLICATION          = 10,
	EFI_BOOT_SERVICE_DRIVER  = 11,
	EFI_RUNTIME_DRIVER       = 12,
	EFI_ROM                  = 13,
	XBOX                     = 14,
	WINDOWS_BOOT_APPLICATION = 16,
}

IMAGE_DLLCHARACTERISTICS :: distinct bit_set[IMAGE_DLLCHARACTERISTIC; u16]
IMAGE_DLLCHARACTERISTIC :: enum u16 {
	HIGH_ENTROPY_VA       = 5,
	DYNAMIC_BASE          = 6,
	FORCE_INTEGRITY       = 7,
	NX_COMPAT             = 8,
	NO_ISOLATION          = 9,
	NO_SEH                = 10,
	NO_BIND               = 11,
	APPCONTAINER          = 12,
	WDM_DRIVER            = 13,
	GUARD_CF              = 14,
	TERMINAL_SERVER_AWARE = 15,
}



OPTIONAL_HEADER_MAGIC_PE32      :: 0x010b
OPTIONAL_HEADER_MAGIC_PE32_PLUS :: 0x020b

IMAGE_SCN_ALIGN_16BYTES  :: 0x00500000
IMAGE_SCN_ALIGN_32BYTES  :: 0x00600000
IMAGE_SCN_ALIGN_64BYTES  :: 0x00700000
IMAGE_SCN_ALIGN_128BYTES :: 0x00800000
IMAGE_SCN_ALIGN_256BYTES :: 0x00900000
IMAGE_SCN_ALIGN_512BYTES :: 0x00A00000

IMAGE_SCN_MEM_SHARED  :: 0x10000000
IMAGE_SCN_MEM_EXECUTE :: 0x20000000
IMAGE_SCN_MEM_READ    :: 0x40000000
IMAGE_SCN_MEM_WRITE   :: 0x80000000