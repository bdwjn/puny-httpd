;
; DATA / BSS section
;

sockaddr:
  sin_family: db 0x00, 0x00  ; AF_INET
  sin_port  : db 0x30, 0x39  ; port 12345
  ; The last 12 bytes are zero, so don't define them.
  ; Linux will zero-initialize memory.
  ;   sin_addr  : dd 0           ; INADDR_ANY
  ;   sin_zero  : dd 0, 0        ; zero

BSS_SIZE          EQU (0x10000 + 0x10000 * 32)
