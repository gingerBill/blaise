package main

import "core:os"
import "core:bytes"

imp_exit:   u32
imp_scanf:  u32
imp_printf: u32

s_fmt_addr: u32
p_fmt_addr: u32

IMPORT_SIZE :: 100
TEXT_BASE   :: 0x1000
IMAGE_BASE  :: 0x400000

imports_buf: [512]byte

create_imports :: proc() -> (imports: []byte) {
	imports = imports_buf[:]

	put_i32(imports[12:], TEXT_BASE+56) // name rva
	put_i32(imports[16:], TEXT_BASE+40) // first thunk
	// thunk array
	put_i32(imports[40:], TEXT_BASE+67)
	put_i32(imports[44:], TEXT_BASE+74)
	put_i32(imports[48:], TEXT_BASE+82)

	copy(imports[56:], "msvcrt.dll\x00")
	copy(imports[67:], "\x00\x00exit\x00")
	copy(imports[74:], "\x00\x00scanf\x00")
	copy(imports[82:], "\x00\x00printf\x00")
	copy(imports[91:], "%d\x00")
	copy(imports[94:], "%d\n\x00")

	imports = imports[:IMPORT_SIZE]

	imp_exit   = IMAGE_BASE + TEXT_BASE + 40
	imp_scanf  = IMAGE_BASE + TEXT_BASE + 44
	imp_printf = IMAGE_BASE + TEXT_BASE + 48

	s_fmt_addr = IMAGE_BASE + TEXT_BASE + 91
	p_fmt_addr = IMAGE_BASE + TEXT_BASE + 94

	return
}

write_exe :: proc(filename: string, code: []byte, imports: []byte) {
	write_padding :: proc(b: ^bytes.Buffer, n: int) {
		for _ in 0..<n {
			bytes.buffer_write_byte(b, 0)
		}
	}
	write_ptr :: proc(b: ^bytes.Buffer, ptr: ^$T, n := 0) {
		bytes.buffer_write_ptr(b, ptr, size_of(T)+n)
	}


	b := &bytes.Buffer{}
	defer bytes.buffer_destroy(b)

	code_pad := padding(len(code), 512)
	code_len := len(code) + code_pad

	// DOS header.
	bytes.buffer_write_string(b, "MZ")
	write_padding(b, 58) // skip loads of crap
	bytes.buffer_write_string(b, "\x40\x00\x00\x00")

	write_ptr(b, &PEFileHeader{
		Magic   = "PE\x00\x00",
		Machine = IMAGE_FILE_MACHINE_I386,
		NumberOfSections = 1,
		SizeOfOptionalHeader = size_of(OptionalHeader32),
		Characteristics = {.BIT32_MACHINE, .EXECUTABLE_IMAGE,
		                   .DEBUG_STRIPPED, .RELOCS_STRIPPED,
		                   .LINE_NUMS_STRIPPED, .LOCAL_SYMS_STRIPPED},
	})

	write_ptr(b, &OptionalHeader32{
		Magic      = OPTIONAL_HEADER_MAGIC_PE32,
		SizeOfCode = u32(code_len),

		AddressOfEntryPoint     = u32(gen.ep),
		BaseOfCode              = TEXT_BASE,
		BaseOfData              = TEXT_BASE,
		ImageBase               = IMAGE_BASE,

		SectionAlignment        = 4096,
		FileAlignment           = 512,

		MajorSubsystemVersion   = 4,
		MinorSubsystemVersion   = 0,

		SizeOfImage             = u32(code_len + padding(code_len, 0x1000) + 0x1000),
		SizeOfHeaders           = 512,

		Subsystem = .WINDOWS_CUI,

		DllCharacteristics = {.NX_COMPAT},

		SizeOfStackReserve = 0x200000,
		SizeOfStackCommit  = 0x001000,
		SizeOfHeapReserve  = 0x100000,
		SizeOfHeapCommit   = 0x001000,

		NumberOfRvaAndSizes = 16,

		DataDirectory = {
			0 = {},
			1 = {VirtualAddress=TEXT_BASE, Size=u32(len(imports))},
		},
	})

	write_ptr(b, &SectionHeader32{
		Name = ".blaise\x00",
		VirtualSize    = u32(code_len),
		VirtualAddress = TEXT_BASE,

		SizeOfRawData    = u32(code_len),
		PointerToRawData = 512,

		Characteristics = IMAGE_SCN_ALIGN_16BYTES|IMAGE_SCN_MEM_EXECUTE|IMAGE_SCN_MEM_READ|IMAGE_SCN_MEM_WRITE,
	})

	// pe header padding
	write_padding(b, padding(len(b.buf), 512))

	bytes.buffer_write(b, code)
	write_padding(b, code_pad)

	os.write_entire_file(filename, bytes.buffer_to_bytes(b))
}