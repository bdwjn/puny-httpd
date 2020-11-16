;
; eax = socket(AF_INET=2, SOCK_STREAM=1, 0)
;
	; At this point eax=359, ebx=2, ecx=0, edx=0 (see entry.asm), and we only need to 'inc ecx'.
	inc ecx
	int 0x80

;
; set_sockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &rval, sizeof(rval))
;
	xchg eax, ebx ; eax=2   ebx=server_fd ecx=1 edx=0
	xchg eax, edx ; eax=0   ebx=server_fd ecx=1 edx=2=SO_REUSEADDR
	; any nonzero value will enable the SO_REUSEADDR option, so we push a value
	; that we can use later: the initial value of 'fd_set'
	push 8        ; eax=0   ebx=server_fd ecx=1 edx=2 [esp] = 8
	mov esi, esp  ; eax=0   ebx=server_fd ecx=1 edx=2 [esi] = 8
	mov ax, 366   ; eax=366 ebx=server_fd ecx=1 edx=2 [esi] = 8
	mov di, 4     ; eax=366 ebx=server_fd ecx=1 edx=2 [esi] = 8 edi=4

	int 0x80

;
; fcntl(server_fd, F_SETFL=4, O_RDWR=2 | O_NONBLOCK=2048) // make the socket non-blocking
;
	mov al, 55
	mov ecx, edi
	mov dh, 8
	int 0x80

;
; bind(server_fd, (sockaddr*) &addr, sizeof(addr))
;
	mov ax, 361
	mov ecx, sockaddr
	shr edx, 7       ; (2048|2)>>7 = 16 = sockaddr_len
	int 0x80

;
;	listen(server_fd, 16)
;
	mov ax, 363
	mov ecx, edx
	int 0x80

	push eax         ; esp -> { 0, fd_set }

main_loop:

	pop edx          ; edx = 0, esp -> { fd_set }

	;bsr ebx, [esp]   ; ebx = max_fd
	;inc ebx          ; ebx = max_fd + 1
	
	mov bl, 32       ; ebx is always a previous fd, so it's <256

	push dword [esp] ; esp -> { fd_set_readable, fd_set }


;
; select(maxfd+1, &fd_set_readable, 0, 0, &timeout)
;
	xor eax, eax
	mov al, 0x8E     ; eax = select
	                 ; ebx = 32
	mov ecx, esp     ; ecx = &fd_set_readable
	                 ; edx = 0
	xor esi, esi     ; esi = 0

	push eax         ; esp -> { timeout, fd_set_readable, fd_set }
	push eax         ; number of seconds = 0x8E = 142
	mov edi, esp
	int 0x80
	pop eax          ; esp -> { fd_set_readable, fd_set }
	pop eax

next_readable_fd:

	bsr ebx, [esp]   ; ebx = fd
	jz main_loop

	btc [esp], ebx

	; if (fd == server_fd)
	cmp ebx, 3
	jne end_if_server_fd
		;
		; eax = clientfd = accept(server_fd, null, null, SOCK_NONBLOCK=2048)
		;
		mov eax, 364 ; eax = accept
		             ; ebx = server_fd
		xor ecx, ecx ; ecx = 0
		             ; edx = 0
		mov esi, 2048; esi = SOCK_NONBLOCK

		int 0x80

		bts [esp+4], eax ; set the bit in master fd_set

		mov cl, al   ; ecx = 00   00 00 <fd>
		bswap ecx    ; ecx = <fd> 00 00 00   = 16 MiB per buffer

		mov dword [esp+4*eax-128], ecx ; reset the pointer for this clientfd

jmp_next_readable_fd:
		jmp next_readable_fd

	end_if_server_fd:

	;
	; eax = read(fd, &buffer[fd][bytesRead], 255)
	;

	xor eax, eax
	mov al, 3                  ; eax = sys_read
	                           ; ebx = fd
	mov ecx, [esp+4*ebx-128]
	dec dl                     ; edx = 255
	int 0x80
	
	add ecx, eax               ; ecx = &buffer[fd][bytesRead]

	mov [esp+4*ebx-128], ecx   ; update bytesRead
	
	; if (client closed connection || buffer full)
	cmp ch, dl                 ; more than 0xff00 bytes? buffer is full
		inc dl             ; edx = 0
		jnc close
	test eax, eax
		jz close

	cmp cx, 7                  ; don't parse with <7 bytes
	jl next_readable_fd

	mov ebp, ebx               ; ebp = socket
	mov esi, ecx
	xor si, si
	mov ebx, esi               ; esi = ebx = start of buffer

	; if (request doesn't start with "GET /")
	lodsd
	cmp eax, 'GET '
	jne if_get_parse_failed
	lodsb
	cmp al, '/'
	je end_if_get_parse_failed

	if_get_parse_failed:
		mov byte [esi], dl ; clear the first byte so the parser throws a bad request
	end_if_get_parse_failed:

next_char:
	xchg ah, al

	lodsb
	cmp al, ' '
		jg end_if_space_or_newline ; if (al>' ') it's neither space or newline
		je finish_response         ; else if (al==' ') it's a space
	cmp al, 13                 ; else if (al==13) it's a newline
		je finish_response

	jump_error_400:
		mov al, 0xFF
		jmp error400       ; else it's a control char: 400 Bad request
	end_if_space_or_newline:
	cmp ax, './'               ; don't allow /.
		je jump_error_400

	cmp si, cx
	jl next_char               ; do { next_char } while (pos < bytesRead)

	jmp jmp_next_readable_fd   ; too far from next_readable_fd for a short jump

close:
	btc [esp+4], ebx           ; remove from master fd_set
	xor eax, eax
	mov al, 6
	int 0x80                   ; close(fd)
	jmp jmp_next_readable_fd   ; too far from next_readable_fd for a short jump

finish_response:
	dec esi
	mov byte [esi], dl         ; buffer[fd][esi] = 0; // zero-terminate the filename

	xor eax, eax
	mov al, 5                  ; eax = open(filename, O_RDWR, 0)
	mov dword [ebx], 'html'    ; change "GET /bla.txt" into "html/bla.txt"
	xor ecx, ecx
	mov cl, 2                  ; ecx = O_RDWR
	int 0x80

error400:
	mov dword [ebx], `400\0`

	cmp al, 0xFE               ; if (ENOENT) error 404
	jne end_if_not_found
		mov byte [ebx+2], '4' ; turn 400 into 404
	end_if_not_found:

	cmp al, 0xF3               ; if (EACCES) error 403
	jne end_if_perm_denied
		mov byte [ebx+2], '3' ; turn 400 into 403
	end_if_perm_denied:

	cmp al, 0xEB               ; if (EISDIR)...
	jne end_if_directory
		; ...remove any trailing slash
		cmp byte [esi-1], '/'
		jne end_if_trailing_slash
			dec esi
		end_if_trailing_slash:
		
		; ...add "/index.html" to the filename
		add esi, 12
		xchg esp, esi
		push `tml\0`
		push `ex.h`
		push `/ind`
		xchg esp, esi
		
		; ...and retry
		jmp finish_response
	end_if_directory:

	jae send_header_and_file
		mov byte [ebx], '2' ; turn 400 into 200

send_header_and_file:
	; open ebx, sendfile it, then if (!CF) sendfile eax
	
	; eax = CF ? file descriptor : undefined
	; ebx = header filename
	; ecx = (undefined)
	; edx = 0
	; esi = (unused) end of filename
	; ebp = socket descriptor

	mov edi, eax

;
; open(header_filename, O_RDONLY, 0)
;
	mov eax, edx     ; do not use XOR as it modifies the CF
	mov al, 5
	mov ecx, edx

	int 0x80


sendfile:
;
; sendfile(socket_fd, file_fd, 0, max=esi)
;

	xchg ecx, eax    ; eax = 0, ecx = file_fd
	mov al, 0xBB     ; sendfile
	mov ebx, ebp     ; ebx = socket_fd
	                 ; esi = 0x00200000 + 0x10000 * sockfd which is
	                 ; roughly 2MB, this is a nice value for sendfile
	                 ; so we don't explicitly set it.
	int 0x80
	
	; close(file_fd)
	mov eax, edx
	mov al, 6
	xchg ebx, ecx    ; ebx = file_fd, ecx = socket_fd
	int 0x80
	xchg ebx, ecx    ; ebx = socket_fd (required to close it)

	jnc close

	clc
	mov eax, edi

	jmp sendfile
