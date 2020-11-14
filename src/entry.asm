BITS 32
  
	org     0x00200000              ; offset must be 0x0020000 to make
	                                ; e_phentsize=0x0020 and e_ehsize=0x0000

	db      0x7F, "ELF"             ; e_ident
	db      1, 1, 1, 0,

prestart:
	; we can put 8 bytes of program code here
	mov ax, 359 ; 4 bytes
	inc ebx     ; 1 byte
	inc ebx     ; 1 byte
	jmp _start  ; 2 bytes

	dw      2                       ; e_type
	dw      3                       ; e_machine
	dd      1                       ; e_version
	dd      prestart                ; e_entry
	dd      phdr - $$               ; e_phoff
phdr:
	dd      1                       ; e_shoff       ; p_type
	dd      0                       ; e_flags       ; p_offset
	dd      $$                      ; e_ehsize      ; p_vaddr
	                                ; e_phentsize
	dw      1                       ; e_phnum       ; p_paddr
	dw      0                       ; e_shentsize
	dd      filesize                ; e_shnum       ; p_filesz
	                                ; e_shstrndx
	dd      filesize + BSS_SIZE                     ; p_memsz
timeout:
	dd      7                                       ; p_flags (the entire program is mode R/W/X)
	dd      0x1000                                  ; p_align

_start:

	%include "code.asm"
	%include "data.asm"

filesize EQU $-$$
