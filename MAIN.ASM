.model tiny
.286
.code
org 100h
locals @@

Start:
    ; save the old 09 int handler
    mov ax, 3509h
    int 21h
    push es
    pop Old09IntSeg
    mov Old09IntOfs, bx

    ; save the old 08 int handler
    mov ax, 3508h
    int 21h
    push es
    pop Old08IntSeg
    mov Old08IntOfs, bx

    ; rewrite the 09 int handler
    push 0h
    pop es
    mov bx, 4 * 09h

    cli
    
    mov ax, offset Popup09Int
    mov es:[bx], ax

    push cs
    pop ax
    mov es:[bx + 2], ax

    sti

    ; rewrite the 08 int handler
    mov bx, 4 * 08h

    cli
    
    mov ax, offset UpdateScreen
    mov es:[bx], ax

    push cs
    pop ax
    mov es:[bx + 2], ax

    sti

    ; finish the program and leave it in the memory
    mov ax, 3100h
    mov dx, offset EOP
    shr dx, 4
    inc dx ; dx = <size of program> // 16 + 1
    int 21h

;----------------------------------------------------------
; An 09 interrupt handler.
; Updates border's state (visibility) based on key presses
; Calls the old handler in the end
;----------------------------------------------------------
; Entry: -
; Assumes: -
; Returns: -
; Destr: -
;----------------------------------------------------------
Popup09Int proc
    ; save all used registers
    push ax bx cx si di ds es

    ; if 'F11' key was pressed - start showing the border
    in al, 60h
    cmp al, 57h
    jne @@Case2

    ; save the screen before showing the border
    push ds

    push 0B800h
    pop ds
    push 0B800h
    pop es

    mov si, 0h
    mov di, 80 * 25 * 2
    mov cx, 12d
    mov bx, 15d
    call MoveMemRegion

    pop ds

    mov IsBorderOnScreen, 01h

@@Case2:
    ; if 'F12' key was pressed - stop updating the border
    cmp al, 58h
    jne @@Exit
    mov IsBorderOnScreen, 00h

    ; load the region of screen where the border was drawn
    push ds

    push 0B800h
    pop ds
    push 0B800h
    pop es

    mov di, 0h
    mov si, 80 * 25 * 2
    mov cx, 12
    mov bx, 15
    call MoveMemRegion

    pop ds

@@Exit:
    ; restore all used registers
    pop es ds di si cx bx ax
    ; far jmp to the old int handler
    db 0EAh
    Old09IntOfs dw 0h
    Old09IntSeg dw 0h
endp
;----------------------------------------------------------

;----------------------------------------------------------
; Prints some elements from the stack. Elems are popped.
;----------------------------------------------------------
; Entry: DX - number of elems to print
;        DI - vmem address of the start of the string
;        CH - color byte of the text
;        STACK - first DX elems will be popped and printed
; Assumes: -
; Returns: -
; Destr: AX, BX, DI, DX, ES, CL
;----------------------------------------------------------
PrintStack proc
    ; set es to start of vmem
    push 0B800h
    pop es

    ; save function's return address
    pop ax

@@PrintElem:
    ; print the top elem (word-sized) as a hex
    pop bx
    push ax
    call PrintWord 
    pop ax

    ; go to a new line on screen
    add di, 152d

    sub dx, 01h
    cmp dx, 0h
    jg @@PrintElem

    ; restore fn's return address
    push ax
    ret
endp
;----------------------------------------------------------

;----------------------------------------------------------
; Prints a machine word in hex on the screen
;----------------------------------------------------------
; Entry: BX - word to print
;        CH - color of the text
;        DI - vmem address of the start of the string
; Assumes: ES = 0B800h
; Returns: -
; Destr: AX, CL, DI
;----------------------------------------------------------
PrintWord proc
    xor cl, cl
@@PrintSym:
    ; put 4 bits from BX into AX
    ; (starting from bit #CL from the left)
    mov ax, bx
    shl ax, cl
    shr ax, 12d
    add ax, 30h

    ; Check if AX is a letter in hex, adjust it if it is
    cmp ax, 3Ah
    jb @@WriteToMem
    add ax, 07h

@@WriteToMem:
    ; Print AL with color CH
    mov ah, ch
    STOSW

    ; Increase CL to take next 4 bits from BX
    add cl, 04h
    cmp cl, 10h
    jb @@PrintSym

    ret
endp
;----------------------------------------------------------

;----------------------------------------------------------
; Prints a label from memory on the screen
;----------------------------------------------------------
; Entry: DI - vmem address of the start of the label
;        DS - sector of the label to print
;        SI - address of the label to print
;        CX - length of the label
;        AL - color byte of the label
; Assumes: -
; Returns: -
; Destroys: ES, DI, SI, CX
; Note: in label ';' symbol means new line
;----------------------------------------------------------
PrintLabel proc
    ; set ES to the start of vmem
    push 0B800h
    pop es

    ; save address of the start of the str
    push di

@@Loop:
    ; if ';' is encountered - go to new line on screen
    cmp byte ptr ds:[si], ';'
    je @@NewLine

    ; print a letter from label and it's color from AL
    MOVSB
    STOSB
    jmp @@Next

@@NewLine:
    inc si
    pop di
    add di, 160d
    push di

@@Next:
    loop @@Loop

    pop di
    ret
endp
;----------------------------------------------------------

;----------------------------------------------------------
; Draws a border on screen
;----------------------------------------------------------
; Entry: AL - color of the border
;        DS - sector of the control string
;        SI - offset from DS of the control string
;        DI - vmem address of the top left corner
;        BX - height of the border (3-80)
;        CX - width of the border (3-25)
; Assumes: -
; Returns: -
; Destr: AH, BX, ES, SI, DI
;----------------------------------------------------------
DrawBorder proc
    push 0B800h
    pop es          ; ES = 0B800h

    CLD             ; DF = 0

    push di

    ;convert bx and cx to the size of the middle part
    sub bx, 02h
    sub cx, 02h


    ;top left corner
    MOVSB
    STOSB

    ;top border
    push cx
    mov ah, al
    LODSB
    REP STOSW
    pop cx

    ;top right corner
    LODSB
    STOSW

    pop di
    add di, 160d

    ;middle
    @@Next:
        push di
        push si

        LODSB
        STOSW

        push cx
        LODSB
        REP STOSW
        pop cx

        LODSB
        STOSW

        pop si
        pop di
        add di, 160d
        dec bx
        cmp bx, 0h
        jne @@Next

    add si, 03h

    ;bottom left corner
    LODSB
    STOSW

    ;bottom border
    push cx
    LODSB
    REP STOSW
    pop cx

    ;bottom right corner
    LODSB
    STOSW

    mov al, ah

    ret
endp
;---------------------------------------------------

;----------------------------------------------------------
; 08 interrupt handler.
; Draws a border with registers on the screen each tick
; (if IsBorderOnScreen is true).
; Calls the old interrupt.
;----------------------------------------------------------
; Entry: -
; Assumes: -
; Returns: -
; Destr: -
;----------------------------------------------------------
UpdateScreen proc
    ; save all used registers
    push ax bx cx dx ds si di es bp

    ; fill stack with current register values to print them later
    push cs ss es ds sp bp di si dx cx bx ax

    ; take IP of where the interrupt occured from the stack
    ; and push it back to print later
    mov bp, sp
    mov bx, ss:[bp + 21 * 2] ; 21 = number of elems pushed on stack
    push bx

    ; don't draw anything if IsBorderOnScreen is false
    cmp IsBorderOnScreen, 01h
    jne @@PopAndExit

    push cs
    pop ds

    ; draw the border (15 * 12)
    mov al, 05h
    mov si, offset BorderCtrlStr
    mov di, 0h
    mov bx, 15
    mov cx, 12
    call DrawBorder

    ; print the label (names of registers)
    mov cx, 51d
    mov di, 164d
    mov si, offset LabelStr
    mov al, 05h
    call PrintLabel 
    
    ; print the registers from the stack
    mov di, 172d
    mov ch, 05h
    mov dx, 0Dh
    call PrintStack

    jmp @@Exit

@@PopAndExit:
    ; 'pop' saved registers from the stack
    add sp, 13d * 2d
@@Exit:
    ; restore used registers
    pop bp es di si ds dx cx bx ax

    ; far jmp to the old int handler
    db 0EAh
    Old08IntOfs dw 0h
    Old08IntSeg dw 0h
endp
;----------------------------------------------------------

;----------------------------------------------------------
; Moves a rectangular region of memory
; (from DS:SI to ES:DI)
;----------------------------------------------------------
; Entry: ES - sector of the saving region
;        DS - sector of the region to save
;        SI - offset of the saving region
;        DI - offset of the region to save
;        CX - width of the region
;        BX - height of the region
; Assumes: -
; Returns: -
; Destr: SI, DI, BX
;----------------------------------------------------------
MoveMemRegion proc
    ; save starts of regions
    push di
    push si
@@LoopY:
    push cx
    REP MOVSW
    pop cx

    ; move to a new line in both mem regions
    pop si
    pop di
    add di, 160d
    add si, 160d
    push di
    push si

    dec bx
    cmp bx, 0h
    jne @@LoopY
    
    pop di
    pop si
    
    ret
endp
;----------------------------------------------------------

BorderCtrlStr db '…Õª∫ ∫»Õº' ; border's simbols: <left top><top>right top><left mid>...
LabelStr db 'IP:;AX:;BX:;CX:;DX:;SI:;DI:;BP:;SP:;DS:;ES:;SS:;CS:' ; labels to print on the border
IsBorderOnScreen db 0h  ; state of the border (visible or not)

EOP:    ; end of the program

end Start
