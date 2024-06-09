org 0x7c00      ; BIOS looks here for the first boot block
bits 16         ; Tell assembler we are using 16-bit code (16 bits always starts in 16 bit)

%define ENDL 0x0D, 0x0A

start: 
    jmp main

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

; Main label to mark where code begins
main:
    ; Setup data segments
    mov ax, 0
    mov ds, ax
    mov es, ax

    ; Setup stack
    mov ss, ax
    mov sp, 0x7c00 ; Stack grows down from where we are loaded in memory

    ; Print message
    mov si, msg_hello
    call puts

    hlt

.halt:
    jmp .halt

msg_hello: db 'hello world!', ENDL, 0

; $-$$ gives the size of our program to this point measured in bytes
times 510-($-$$) db 0

; dw is a two byte (1 word) constant
dw 0xAA55
