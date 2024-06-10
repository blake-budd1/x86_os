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


    ; Setup data segments
    mov ax, 0
    mov ds, ax
    mov es, ax

    ; Setup stack
    mov ss, ax
    mov sp, 0x7c00                  ; Stack grows down from where we are loaded in memory

    ; Make sure that the code segment is 0
    push es
    push word .after
    retf
    ; some bios might start at 0x7c0 
.after:


    ; Read something from floppy disk
    ; BIOS should set DL to drive number
    mov [ebr_drive_number], dl

    ; Print message
    mov si, msg_loading
    call puts

    ; Read drive parameters:
    push es
    mov ah, 0x08
    int 0x13
    jc floppy_error
    pop es

    and cl, 0x3F                        ; Remove the top two bits
    xor ch, ch
    mov [bdb_sectors_per_track], cx     ; Sector count

    inc dh
    mov [bdb_heads], dh                 ; head count

    ; read FAT root directory
    mov ax, [bdb_sectors_per_fat]       ; LBA of root directory = reserved + fats * sectors_per_fat
    mov bl, [bdb_fat_count]
    xor bh, bh 
    mul bx                              ; ax = (fats * sectors_per_fat)
    add ax, [bdb_reserved_sectors]      ; ax = LBA of root directory
    push ax

    mov ax, [bdb_sectors_per_fat]
    shl ax, 5
    xor dx, dx
    div word [bdb_bytes_per_sector]     ; number of sectors we need to read

    test dx, dx                         ; if dx != 0 add 1
    jz .root_dir_after
    inc ax

.root_dir_after:
    ; read the root directory
    mov cl, al                          ; number of sectors to read = size of root directory
    pop ax
    mov dl, [ebr_drive_number]          ; dl = drive number (previously saved)
    mov bx, buffer
    call disk_read

    ; search for kernel.bin
    xor bx, bx
    mov di, buffer

.search_kernel
    mov si, file_kernel_bin
    mov cx, 11
    push di
    repe cmpsb                          ; compare string bytes (si and di)
    pop di
    je .found_kernel

    add di, 32
    inc bx
    cmp bx, [bdb_dir_entries_count]
    jl .search_kernel

    ; Kernel not found.
    jmp kernel_not_found_error


.found_kernel:
    ; Save the first cluster value di
    mov ax, [di+26]     ; first logical cluster field
    mov [kernel_cluster], ax

    ; load FAT from disk into memory
    mov ax, [bdb_reserved_sectors]
    mov bx, buffer
    mov cl, [bdb_sectors_per_fat]
    mov dl, [ebr_drive_number]
    call disk_read

    ; read kernel and process FAT chain
    mov bx, KERNEL_LOAD_SEGMENT
    mov es, bx
    mov bx, KERNEL_LOAD_OFFSET

.load_kernel_loop:
    mov ax, [kernel_cluster]            ; First cluser = (kernel_cluster - 2) * sectors_per_cluster + start_sector
    add ax, 31                          ; start sector = reserved + fats + root directory size = 1 + 18 + 134 = 33

    mov cl, 1
    mov dl, [ebr_drive_number]
    call disk_read

    add bx, [bdb_bytes_per_sector]      ; will overflow if kernel is larger than 64 kilobytes

    ; Compute location of next cluser
    mov ax, [kernel_cluster]
    mov cx, 3
    mul cx
    mov cx, 2
    div cx

    mov si, buffer
    add si, ax
    mov ax, [ds:si]                     ; read entry from FAT table at index ax

    or dx, dx
    jz .even 

.odd:
    shr ax, 4
    jmp .next_cluser_after

.even:
    and ax, 0x0FFF

.next_cluser_after:
    cmp ax, 0x0FF8                      ; end of chain
    jae .read_finish
    mov [kernel_cluster], ax
    jmp .load_kernel_loop

.read_finish:
    ; boot device in dl
    mov dl, [ebr_drive_number]

    ; set segment register
    mov ax, KERNEL_LOAD_SEGMENT
    mov ds, ax
    mov es, ax

    jmp KERNEL_LOAD_SEGMENT:KERNEL_LOAD_OFFSET

    jmp wait_key_and_reboot             ; should never happen

    cli                                 ; Disable the interrupts
    hlt

floppy_error:
    mov si, msg_read_failed
    call puts
    jmp wait_key_and_reboot

kernel_not_found_error:
    mov si, msg_kernel_not_found
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
; Prints a string to the screen
; Params:
;   - ds:si points to string
;
puts:
    ; save registers we will modify
    push si
    push ax
    push bx

.loop:
    lodsb               ; loads next character in al
    or al, al           ; verify if next character is null?
    jz .done

    mov ah, 0x0E        ; call bios interrupt
    mov bh, 0           ; set page number to 0
    int 0x10

    jmp .loop

.done:
    pop bx
    pop ax
    pop si    
    ret

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



msg_loading:                db 'Loading...', ENDL, 0
msg_read_failed:            db 'Read from disk has failed.', ENDL, 0
msg_kernel_not_found        db 'KERNEL.bin not found. ', ENDL, 0
file_kernel_bin:            db 'KERNEL  BIN'
kernel_cluster:             dw 0'
KERNEL_LOAD_SEGMENT         equ 0x2000
KERNEL_LOAD_OFFSET          equ 0
; $-$$ gives the size of our program to this point measured in bytes
times 510-($-$$) db 0

; dw is a two byte (1 word) constant
dw 0xAA55

buffer: