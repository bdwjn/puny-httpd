;
; DATA / BSS section
;

header            db '200.html'

	sockaddr:
	  sin_family: db 0x00, 0x00  ; AF_INET
	  sin_port  : db 0x30, 0x39  ; port 12345
	  ; sin_port  : db 0x00, 0x50  ; port 80

	  ; the last 12 bytes are zero, so don't define them and
	  ; assume Linux zero-initialises memory
	  ;	  sin_addr  : dd 0           ; INADDR_ANY
	  ;	  sin_zero  : dd 0, 0        ; zero
	sockaddr_len: equ ($ - sockaddr + 12)

stat              EQU ($ + 12) ; 88 bytes

buffer_pos        EQU ($ + 12 + 88)

fd_set            EQU (0x0020FFFC) ; must precede fd_set_read
fd_set_read       EQU (0x00210000) ; must precede timeout
timeout           EQU (0x00210004) ; must end in 0x0004

buffer            EQU (0x00220000) ; make the read buffers 64k aligned so the lower 16 bits of the pointer = number of bytes read


BSS_SIZE          EQU (0x20000 + 0x10000 * 32)
