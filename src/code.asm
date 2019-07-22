;
; eax = socket(AF_INET=2, SOCK_STREAM=1, 0)
;
	; __syscall 359, 2, 1, 0

	; At this point eax=359, ebx=2, ecx=0, edx=0 (see entry.asm), and we only need to "inc ecx".
	inc ecx
	int 0x80

;
; set_sockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &rval, sizeof(rval))
;
	; __syscall 366, socket, 1, 2, fd_set_read, 4

	xchg eax, ebx ; eax=2   ebx=socket ecx=1 edx=0
	xchg eax, edx ; eax=0   ebx=socket ecx=1 edx=2
	push 1        ; eax=0   ebx=socket ecx=1 edx=2 [esp] = 1
	mov esi, esp  ; eax=0   ebx=socket ecx=1 edx=2 [esi] = 1
	mov ax, 366   ; eax=366 ebx=socket ecx=1 edx=2 [esi] = 1
	mov di, 4     ; eax=366 ebx=socket ecx=1 edx=2 [esi] = 1 edi=4
	int 0x80

;
; fcntl(socket, F_SETFL=4, O_RDWR=2 | O_NONBLOCK=2048) // make the socket non-blocking
;
	; __syscall 55,   socket,    4,    2048 | 2

	mov al, 55
	mov ecx, edi
	mov dh, 8
	int 0x80

;
; bind(serverSock, (sockaddr*) &addr, sizeof(addr))
;
	; __syscall 361, socket, sockaddr, sockaddr_len
		
	mov ax, 361
	mov ecx, sockaddr
	shr edx, 7 ; (2048|2)>>7 = 16 = sockaddr_len
	int 0x80

;
;	listen(serverSock, 16)
;
	; __syscall 363, ebx, 16

	mov ax, 363
	mov ecx, edx
	int 0x80

	bts dword [fd_set], ebx ; set the server socket bit
	
	xor edx, edx    ; edx = 0 and stays 0 throughout the program
	
	; esp -> ('html', 0)
	push byte 0
	push dword 'html'

main_loop:
	; copy 'fd_set' to 'fd_set_read'
	mov esi, fd_set ; esi = fd_set
	lodsd           ; esi = fd_set_read   eax = [fd_set]
	mov edi, esi    ; esi = fd_set_read   eax = [fd_set]   edi = fd_set_read
	stosd           ; esi = fd_set_read   eax = [fd_set]   edi = timeout

	; ebx = maxfd + 1
	bsr ebx, eax
	inc ebx

	; select(maxfd+1, &fd_set_read, 0, 0, &timeout)
	;   mov ecx, timeout
	;   mov byte [ecx], cl     ; Linux may destroy the "timeout" after the select call
	;   __syscall 0x8E, ebx, fd_set_read, 0, 0, esi

	xor eax, eax
	mov al, 0x8E
	
	mov ecx, esi
	xor esi, esi
	mov [edi], di
	int 0x80

nextfd:
	mov esi, fd_set_read
	bsr edi, [esi] ; take the highest fd
	jz main_loop
	btc [esi], edi ; clear it

	mov ebp, buffer_pos ; buffer_pos is used twice in the following code, loading it to ebp saves us 1 byte

	; if (cur_fd == server_fd)
	cmp edi, 3
	jne end_if_server_fd
		; __syscall 364, edi, 0, 0, 2048         ; eax = accept4(serversock, null, null, SOCK_NONBLOCK=2048)
		
		; At this point, the value of eax can be:
		; from select()         : eax = number of readable sockets
		; from a serverfd read  : eax = the new socket fd
		; from a clientfd read  : eax = the total number of bytes in the buffer if it was < 7, or the last parsed byte
		; from a finished client: eax = 6
		mov ax, 364  ; we can be certain that eax<256
		mov ebx, edi ; ebx = socket
		xor ecx, ecx ; ecx = 0
		mov esi, 2048
		int 0x80

		bts [fd_set], eax                   ; set bit in [fd_set]
		mov dword [ebp + 4*eax], ecx ; buffer_pos[n] = 0
		jmp nextfd
		end_if_server_fd:

	; eax=num_readable   ebx=maxfd+1   ecx=fd_set_read   edx=0   esi=0   edi=fd

	mov ecx, edi
	shl ecx, 16
	lea esi, [ebp + 4*edi] ; esi = & buffer_pos[socket]
	add ecx, [esi]
	add ecx, buffer               ; ecx = & buffer[n]

	; read(socket=EDI, &buffer[ buffer_pos[socket] ], 4096)
	; __syscall 3, edi, ecx, 4096
	
	mov al, 3      ; eax was <256
	mov ebx, edi
	mov dh, 16     ; edx was 0 and 4096 = 16<<8
	int 0x80
	xor edx, edx

	test eax, eax  ; if read() == 0, then the connection was closed by client
	jz close

	add [esi], eax ; n = n + eax
	xor cx, cx     ; ecx = buffer
	xchg esi, ecx  ; esi = buffer   ecx = &n

	cmp dword [esi], 7
	jle nextfd     ; don't parse with less than 7 bytes, ("GET /",13,10) is the shortest valid request

	lodsd
	cmp eax, 'GET '
	jne bad_request

	lodsb
	cmp al, '/'
	jne bad_request

	; turn "GET /path" into "html/path"
	mov ebp, [esp]
	mov dword [esi-5], ebp

	mov bl, al ; bl = '/'

	xor eax, eax
	
	next_url_char:
		lodsb

		; if (al==' ' || al=='\n') { finished parsing } else if (al<' ') { bad_request }
		cmp al, ' '
		jg end_if_space_or_newline
		je end_url
			cmp al, 13 ; newline
				je end_url
			; jmp bad_request ; control char
			
			bad_request:
				push '400.'
				xor eax, eax
				jmp send_esp_eax_close
			
			end_if_space_or_newline:

		cmp al, '.'
		jne end_if_dot
			cmp bl, '/'
				je forbidden ; do not allow '/.'
			end_if_dot:

		mov bl, al

		cmp al, 0x7E   ; > 0x7E: extended ascii
			jg bad_request

		cmp si, word [ecx] ; do { next_url_char } while (esi != n);
			jne next_url_char

		jmp nextfd ; finished parsing, didn't find a newline

	end_url:
		dec esi            ; esi = first char past path
		mov byte [esi], dl ; zero-terminate string

		mov ebp, esi       ; ebp = end of path
		xor si, si         ; esi = start of path (read buffers are 16-bit aligned)

		; __syscall 0x6A, esi, stat ; fstat(esi)
		
		mov al, 0x6A
		mov ebx, esi
		mov ecx, stat
		int 0x80

		and eax, eax
			jnz not_found

		bt word [stat+8], 14 ; if (is_directory)
		jnc end_if_dir
			xchg ebp, esp  ; save esp
			add esp, 12    ; esp = 12 bytes past end of URL
			push `tml\0`   ; add ('index.html',0) to the filename
			push `ex.h`
			push `/ind`
			xchg ebp, esp  ; restore esp
			end_if_dir:
		
		;__syscall 5, esi, edx, edx ; eax = open(esi, 0, 0)
		mov al, 5    ; safe because fstat() returned eax=0
		mov ebx, esi
		xor ecx, ecx
		int 0x80
		
		cmp eax, edx
		jl forbidden ; if (open() < 0) { 403 error }
		
		push '200.'

	send_esp_eax_close:           ; esp=(200.html | 400.html | 403.html | 404.html) eax=(resource_fd | 0)
		mov ebp, eax
		
		;__syscall 5, ebx, 0, 0 ; eax = open(ebx=header)
		mov al, 5 ; eax is either 0 or a file descriptor, so assume ah=0
		mov ebx, esp ; ebx -> ("200.html",0)
		pop ecx      ; esp -> ("html",0)
		xor ecx, ecx
		int 0x80

		send_and_close_eax: ; this is run twice, once with eax=header_fd and once more with eax=resource_fd
		
			; __syscall 0xBB, edi, eax, edx, 0x100000 ; sendfile(edi, eax)

			mov ecx, eax ;                                ecx = file_fd
			mov al, 0xBB ; eax = 0xBB                     ecx = file_fd
			mov ebx, edi ; eax = 0xBB   ebx = socket_fd   ecx = file_fd
			mov esi, 0x100000
			int 0x80
			
			; [TODO]
			; The current code assumes sendfile() sends the whole file in one call.
			; I'm not sure how reliable this is for large files. To turn this into a loop
			; will require the file size, which means fseek or fstat calls, which will be
			; expensive in terms of code size.

			; __syscall 6, ecx ; close(file_fd)
			xor eax, eax
			add al, 6
			mov ebx, ecx
			int 0x80

		test ebp, ebp          ; ebp nonzero? then we have a resource file to send
		jz no_resource
			xchg eax, ebp  ; eax = ebp, ebp = 0
			
			jmp send_and_close_eax
			no_resource:

	close:
		; __syscall 6, edi ; close(socket)
		mov al, 6
		mov ebx, edi
		int 0x80
		
		btc [fd_set], edi ; remove EDI from the master fd_set

		jmp nextfd

forbidden:
	push '403.'
	jmp clear_close

not_found:
	push '404.'

clear_close:
	xor eax, eax
	jmp send_esp_eax_close
