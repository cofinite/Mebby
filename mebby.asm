bits 16
org 0x7C00

boot:
    jmp main
    times 3 - ($ - $$) db 0x90
bpb:
    db    " Controls .<."
    db "Arrow/Page: move"
    db "0-9/A-F: set mem"
    db "Enter: exec code"
    %if ($ - bpb) < 59
        %error "BIOS parameter block shouldn't be less than 59 bytes."
    %endif

main:
    xor ax, ax
    mov ss, ax; clear the stack segment
    mov sp, ax; clear the stack ptr (will underflow on push)
    mov ax, 0xB800
    mov es, ax; set the extra segment to the VGA text buffer

    mov ah, 0x00; BIOS INT 10,0: set video mode
    mov al, 0x03; video mode 0x03: 80x25 16 color text
    int 0x10

    push 0x07C0; the segment we would like to look at
    push 0x0000; cursor position
    mov bp, sp

%define MEM_SEG     word [bp + 2]
%define CURSOR_X    byte [bp + 1]
%define CURSOR_Y    byte [bp + 0]

%define KEY_ENTER       0x1C
%define KEY_ARROW_UP    0x48
%define KEY_ARROW_LEFT  0x4B
%define KEY_ARROW_DOWN  0x50
%define KEY_ARROW_RIGHT 0x4D
%define KEY_PAGE_UP     0x49
%define KEY_PAGE_DOWN   0x51

%define ROWS 25
%define COLS 80
%define VIDEO_CHAR_SIZE 2
%define VIDEO_MEM_SIZE (VIDEO_CHAR_SIZE * ROWS * COLS)

%define LOG2_BYTES_PER_ROW 4
%define BYTES_PER_ROW (1 << LOG2_BYTES_PER_ROW)

%define CHARS_PER_BYTE 2

%define CURSOR_X_MAX (CHARS_PER_BYTE * BYTES_PER_ROW - 1)
%define CURSOR_Y_MAX (ROWS - 1)

%define FMT_PADDING_LEFT 14
%define FMT_CHARS_PER_BYTE 3

%macro print 1
    mov al, %1
    call print_char
%endmacro

main_loop:
    mov bl, CURSOR_X; compute character coordinates from logical coordinates
    and bl, 1
    mov al, CURSOR_X
    shr al, 1
    mov bh, FMT_CHARS_PER_BYTE
    mul bh
    add al, FMT_PADDING_LEFT
    add al, bl
    
    mov ah, 0x02; BIOS INT 10,2: set cursor position
    mov bh, 0x00
    mov dl, al
    mov dh, CURSOR_Y
    int 0x10
    
    xor si, si
    xor di, di
    mov ds, MEM_SEG
    .render_row:
        print ' '
        print '['
        mov bx, MEM_SEG
        mov al, bh
        call print_hex
        mov al, bl
        call print_hex
        print ':'
        mov bx, di
        mov al, bh
        call print_hex
        mov al, bl
        call print_hex
        print ']'
        print ' '
        mov cl, BYTES_PER_ROW
        .render_hex:
            print ' '
            mov al, byte [ds:di]
            call print_hex
            inc di
            dec cl
            jnz .render_hex
        print ' '
        call print_char
        sub di, BYTES_PER_ROW
        mov cl, BYTES_PER_ROW
        .render_ascii:
            mov al, byte [ds:di]
            mov ah, al
            sub ah, ' '
            cmp ah, '~' - ' '
            jbe .is_ascii
            mov al, '.'
            .is_ascii:
                call print_char
                inc di
            dec cl
            jnz .render_ascii
        print ' '
        
        cmp si, VIDEO_MEM_SIZE
        jl .render_row
    
	mov ah, 0x00; BIOS INT 16,0: wait for keypress and read
	int 0x16
	
    cmp ah, KEY_ENTER
    je execute
    cmp ah, KEY_ARROW_UP
    je up
    cmp ah, KEY_ARROW_LEFT
    je left
    cmp ah, KEY_ARROW_DOWN
    je down
    cmp ah, KEY_ARROW_RIGHT
    je right
    cmp ah, KEY_PAGE_UP
    je page_up
    cmp ah, KEY_PAGE_DOWN
    je page_down
    
    mov bl, al
    sub al, '0'
    cmp al, '9' - '0'
    jbe write
    sub bl, 'a'
    mov al, bl
    add al, 10
    cmp bl, 'f' - 'a'
    jbe write
    
    jmp main_loop

execute:
    call load_cursor_address
    push 0
    push main_loop
    push ds
    push di
    retf
up:
    cmp CURSOR_Y, 0
    je .scroll
        dec CURSOR_Y
        jmp main_loop
    .scroll:
        dec MEM_SEG
        jmp main_loop
left:
    cmp CURSOR_X, 0
    je .scroll
        dec CURSOR_X
        jmp main_loop
    .scroll:
        mov CURSOR_X, CURSOR_X_MAX
        jmp up
down:
    cmp CURSOR_Y, CURSOR_Y_MAX
    je .scroll
        inc CURSOR_Y
        jmp main_loop
    .scroll:
        inc MEM_SEG
        jmp main_loop
right:
    cmp CURSOR_X, CURSOR_X_MAX
    je .scroll
        inc CURSOR_X
        jmp main_loop
    .scroll:
        mov CURSOR_X, 0
        jmp down
page_up:
    mov bx, MEM_SEG
    dec bh
    mov MEM_SEG, bx
    jmp main_loop
page_down:
    mov bx, MEM_SEG
    inc bh
    mov MEM_SEG, bx
    jmp main_loop
write:
    call load_cursor_address
    mov bh, byte [ds:di]
    mov bl, CURSOR_X
    and bl, 1
    cmp bl, 0
    je .write_high
    .write_low:
        and bh, 0xF0
        or bh, al
        mov byte [ds:di], bh
        jmp right
    .write_high:
        and bh, 0x0F
        shl al, LOG2_BYTES_PER_ROW
        or bh, al
        mov byte [ds:di], bh
        jmp right

load_cursor_address:
    mov bh, 0
    mov bl, CURSOR_Y
    shl bx, LOG2_BYTES_PER_ROW
    mov di, bx
    mov bh, 0
    mov bl, CURSOR_X
    shr bx, 1
    or di, bx
    ret

print_char:
    mov byte [es:si], al
    add si, VIDEO_CHAR_SIZE
    ret

load_digit:
    cmp al, 10
    jge .hex_digit
    add al, '0'
    ret
    .hex_digit:
        sub al, 10
        add al, 'A'
        ret

print_hex:
    mov ah, al
    shr al, 4
    and ah, 0x0F
    call load_digit
    call print_char
    mov al, ah
    call load_digit
    call print_char
    ret

times 510 - ($ - $$) db 0
dw 0xAA55
