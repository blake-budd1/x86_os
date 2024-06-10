org 0x0      ; BIOS looks here for the first boot block
bits 16         ; Tell assembler we are using 16-bit code (16 bits always starts in 16 bit)

%define ENDL 0x0D, 0x0A

start: 
    jmp main


; Main label to mark where code begins
main:
    ; Print hello message
    mov si, msg_hello
    call puts

.halt:
    cli
    hlt

; Prints a string to the screen
; Params: ds:si points to string

puts:
    ; Save registers will be modified
    push si
    push ax

.loop:
    lodsb          ; loads the next character in al
    or al, al       ; verify if next char is null
    jz .done
    
    mov ah, 0x0e    ; call bios interrupt
    mov bh, 0
    int 0x10
    jmp .loop



.done:
    pop ax
    pop si
    ret

msg_hello: db 'hello world from the kernel!', ENDL, 0
