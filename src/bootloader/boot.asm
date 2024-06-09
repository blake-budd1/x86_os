org 0x7c00      ; BIOS looks here for the first boot block
bits 16         ; Tell assembler we are using 16-bit code (16 bits always starts in 16 bit)

%define ENDL 0x0D, 0x0A

;
; FAT12 Header
;
jmp short start
nop

bdb_oem:                        db 'MSWIN4.1'               ; 8 bytes
bdb_bytes_per_sector:           dw 512  
bdb_sectors_per_cluser:         db 1
bdb_reserved_sectors:           dw 1
bdb_fat_count:                  db 2
bdb_dir_entries_count:          dw 0xE0         
bdb_total_sectors:              dw 2880                     ; 2880 * 512 = 1.44 MB
bdb_media_descriptor_type:      db 0x0f0                    ; F0 = 3.5" floppy disck
bdb_sectors_per_fat:            dw 9                        ; 9 sectors/fat
bdb_sectors_per_track:          dw 18
bdb_heads:                      dw 2
bdb_hidden_sectors:             dd 0
bdb_large_sector_count:         dd 0

;
; Extended boot record
;
ebr_drive_number:               db 0                        ; 0x00 Floppy, 0x80 hdd
                                db 0                        ; Reserved
ebr_signature:                  db 0x29
ebr_volume_id:                  db 0x12, 0x34, 0x56, 0x78   ; Serial number, does not change
ebr_volume_lab:                 db 'NANOBTES OS'                 ; 11 buytes, paded with spaces
ebr_system_id:                  db 'FAT12   '               ; 8 bytes

;
; Code goes here
; 


start: 
    jmp main

; Prints a string to the screen
; Params: ds:si points to string

puts:
    ; Save registers will be modified
    push si
    push ax

.loop:
    lodsb                           ; loads the next character in al
    or al, al                       ; verify if next char is null
    jz .done
    
    mov ah, 0x0e                    ; call bios interrupt
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
    mov sp, 0x7c00                  ; Stack grows down from where we are loaded in memory

    ; Read something from floppy disk
    ; BIOS should set DL to drive number
    mov [ebr_drive_number], dl

    mov ax, 1                       ; LBA = 1,second sector from disk
    mov cl, 1                       ; 1 sector to read  
    mov bx, 0x7E00                  ; Data should be after the bootloader
    call disk_read

    ; Print message
    mov si, msg_hello
    call puts

    cli                             ; Disable the interrupts
    hlt

floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

wait_key_and_reboot:
    mov ah, 0
    int 0x16                        ; Wait for keypress
    jmp 0xffff:0                    ; jmp to beginning of BIOS, should reboot
    
.halt
    cli                             ; disable interrupts 
    hlt

; 
; Disk Routines
;

;
; Converts an LBA address to CHS address
; Parameters:
;   -ax: LBA Address
; Returns:
;   - cx [bits 0-5]: sector number
;   - cx [bits 6-15]: cylinder
;   - dh: head

lba_to_chs:
    push ax
    push dx

    xor dx, dx                          ; dx = 0
    div word [bdb_sectors_per_track]    ; ax = LBA / SectorsPerTrack
                                        ; dx = LBA % SectorsPerTrack
    inc dx                              ; dx = (LBA % SectorsPerTrack + 1) = sector
    mov cx, dx                          ; cx = sector

    xor dx, dx                          ; dx = 0
    div word [bdb_heads]                ; ax = (LBA/SectorsPerTrack)/ Heads = cylinder
                                        ; dx = (LBA/SectorsPerTrack) % Heads = head
    mov dh, dl                          ; dh = head
    mov ch, al                          ; ch = lower 8 bits of cylinder
    shl ah, 6                           
    or cl, ah                           ; put upper 2 bits of cylinder in CL

    pop ax
    mov dl, al
    pop ax
    ret


; 
; Read sectors from a disk
; Parameters:
;   - ax: LBA address
;   - cl: number of sectors to read (up to 128)
;   - dl: drive number
;   - es:bx: memory address where to store read data
;
disk_read:
    push ax                             ; Save registers that will be modified
    push bx
    push cx
    push dx
    push di

    push cx                             ; save CL (number of sectors to read)
    call lba_to_chs                     ; compute CHS
    pop ax                              ; AL = number of sectors to read

    mov ah, 0x02
    mov di, 3                           ; retry count

.retry 
    pusha                               ; save all registers
    stc                                 ; set carry flag, some bios dont set it
    int 0x13                            ; catty flag cleared = succcess
    jnc .done                           ; jump if carry not set

    ; retry failed
    popa 
    call disk_reset

    dec di
    test di, di
    jnz .retry

.fail:
    ; all retry attempts have been exhausted
    jmp floppy_error

.done:
    popa

    pop ax                             ; Restore registers that we modified
    pop bx
    pop cx
    pop dx
    pop di
    ret

;
; Reset disk controller
; Paramters:
;   - dl: drive number
;
disk_reset:
    pusha
    mov ah, 0
    stc
    int 0x13
    jc floppy_error
    popa
    ret



msg_hello:                  db 'hello world!', ENDL, 0
msg_read_failed:            db 'Read from disk has failed.', ENDL, 0

; $-$$ gives the size of our program to this point measured in bytes
times 510-($-$$) db 0

; dw is a two byte (1 word) constant
dw 0xAA55
