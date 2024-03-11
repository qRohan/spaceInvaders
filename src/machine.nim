import std/bitops
import std/strformat
import std/sugar

import sdl2/mixer

import i8080/i8080

const
    CLOCK_SPEED = 1996800
    FPS = 59.541985
    CYCLES_PER_FRAME = 33536 #CLOCK / FPS = 33535.99984951795
    SCREEN_WIDTH* = 224
    SCREEN_HEIGHT* = 256

    VRAM_ADDR = 0x2400

type
    SoundsName = enum
        UFO_MOVE_SND,
        SHOOT_LASER_SND,
        PLAYER_DEATH_SND,
        INVADER_DEATH_SND,
        FLEET1_SND,
        FLEET2_SND,
        FLEET3_SND,
        FLEET4_SND,
        UFO_HIT_SND,
        EXTRA_LIFE_SND

    Invaders* = ref object
        cpu: CPU
        memory: array[0x4000, byte]

        next_interrupt: byte
        colored_screen*: bool

        port1*, port2*: byte
        shift_reg: uint16
        shift_offset: byte
        last_out_port3, last_out_port5: byte

        screen_buffer*: array[SCREEN_HEIGHT, array[SCREEN_WIDTH, array[3, byte]]]
        updateTexture*: proc (si: Invaders)

        sounds: array[SoundsName, ChunkPtr]

proc `[]`[I, J, T](mat: array[I, array[J, T]], r: I, c: J): T =
    return mat[r][c]

proc `[]=`[I, J, T](mat: array[I, array[J, T]], r: I, c: J) =
    mat[r][c] = T

proc play_sound(si: Invaders, bank: byte)

proc rb(si: Invaders, address: uint16): byte {.inline.} =
    case address:
        of 0 .. pred(0x4000):
            result = si.memory[address]
        of 0x4000 .. pred(0x6000):
            result = si.memory[address - 0x2000]
        else:
            result = 0

proc wb(si: Invaders, address: uint16, value: byte) {.inline.} =
    case address:
        of 0x2000 .. pred(0x4000):
            si.memory[address] = value
        else:
            discard

proc port_in(si: Invaders, port: byte): byte =
    result = 0xFF
    case port:
        of 0: # 0000pr: INP0 (Mapped in hardware but never used by the code)
            discard
        of 1: # 0001pr: INP1
            result = si.port1
        of 2: # 0002pr: INP2
            result = si.port2
        of 3:
            result = byte(si.shift_reg.bitsliced((8 - int(si.shift_offset)) .. (15 - int(si.shift_offset))) and 0xFF)
        else:
            discard

proc port_out(si: Invaders, port: byte, value: byte) =
    case port:
        of 2: # 0002pw: SHFTAMNT
            si.shift_offset = value and 0x07
        of 3: # 0003pw: SOUND1
            # plays a sound from bank 1
            play_sound(si, 1)
        of 4: # 0004pw: SHFT_DATA
            si.shift_reg = si.shift_reg shr 8
            si.shift_reg = si.shift_reg or (uint16(value) shl 8)
        of 5: # 0005pw: SOUND2
            # plays a sound from bank 2
            play_sound(si, 2)
        of 6: # 0006pw: WATCHDOG
            # The watchdog checks to see if the system has crashed. 
            # If the watchdog doesn't receive a read/write request after a 
            # certain number of clock cycles it resets the whole machine. 
            # This is external circuitry which is not needed to be implemented
            discard
        else:
            discard #TODO




proc init_cpu(si: Invaders) =
    si.cpu = newCPU()

    proc rb(address: uint16): byte =
        # si.memory[address]
        si.rb(address)


    proc wb(address: uint16, value: byte) =
        # si.memory[address] = value
        si.wb(address, value)

    proc port_in(cpu: var CPU, port: byte): byte =
        si.port_in(port)

    proc port_out(cpu: var CPU, port: byte, value: byte) =
        si.port_out(port, value)

    si.cpu.mem = Memory(read_byte: rb, write_byte: wb)
    si.cpu.port_in = port_in
    si.cpu.port_out = port_out

    si.next_interrupt = 0xCF

    si.colored_screen = true

    # Port 1
    # bit 0 = CREDIT (1 if deposit)
    # bit 1 = 2P start (1 if pressed)
    # bit 2 = 1P start (1 if pressed)
    # bit 3 = Always 1
    # bit 4 = 1P shot (1 if pressed)
    # bit 5 = 1P left (1 if pressed)
    # bit 6 = 1P right (1 if pressed)
    # bit 7 = Not connected
    si.port1 = 0
    si.port1.setBit(3)

    # Port 2
    # bit 0 = DIP3 00 = 3 ships  10 = 5 ships
    # bit 1 = DIP5 01 = 4 ships  11 = 6 ships
    # bit 2 = Tilt
    # bit 3 = DIP6 0 = extra ship at 1500, 1 = extra ship at 1000
    # bit 4 = P2 shot (1 if pressed)
    # bit 5 = P2 left (1 if pressed)
    # bit 6 = P2 right (1 if pressed)
    # bit 7 = DIP7 Coin info displayed in demo screen 0=ON
    si.port2 = 0

proc load_sounds(si: Invaders) =
    si.sounds[UFO_MOVE_SND]= loadWAV("sounds/0.wav")
    si.sounds[SHOOT_LASER_SND]= loadWAV("sounds/1.wav")
    si.sounds[PLAYER_DEATH_SND]= loadWAV("sounds/2.wav")
    si.sounds[INVADER_DEATH_SND]= loadWAV("sounds/3.wav")
    si.sounds[FLEET1_SND]= loadWAV("sounds/4.wav")
    si.sounds[FLEET2_SND]= loadWAV("sounds/5.wav")
    si.sounds[FLEET3_SND]= loadWAV("sounds/6.wav")
    si.sounds[FLEET4_SND]= loadWAV("sounds/7.wav")
    si.sounds[UFO_HIT_SND]= loadWAV("sounds/8.wav")
    si.sounds[EXTRA_LIFE_SND]= loadWAV("sounds/9.wav")

proc newInvaders*(): Invaders =
    result = Invaders()
    result.init_cpu()
    result.load_sounds()

proc loadROM*(si: var Invaders, filename: string, startAddr: uint16) =
    var rom = open(filename, fmRead)
    if rom.isNil:
        raise newException(OSError, "Unable to open file")

    var data = collect:
        for character in rom.readAll():
            byte(character)

    if len(data) > 0x800:
        raise newException(OSError, "ROM file is too big to fit in memory")
    else:
        for i in 0..<len(data):
            si.memory[startAddr + i.uint16] = data[i]

        # si.memory[startAddr..<len(data)] = data

    rom.close()

var ufo_move_channel: cint = -1
proc play_sound(si: Invaders, bank: byte) =
    var 
        data = si.cpu.reg.A    
    case bank:
        of 1:
            if data.testBit(0) and not si.last_out_port3.testBit(0):
                if ufo_move_channel != -1 and playing(ufo_move_channel) != 0:
                    discard
                else:
                    ufo_move_channel = playChannel(-1, si.sounds[UFO_MOVE_SND], -1)
            elif not data.testBit(0) and si.last_out_port3.testBit(0):
                if ufo_move_channel != -1 and playing(ufo_move_channel) != 0:
                    discard haltChannel(ufo_move_channel)
            
            if data != si.last_out_port3:
                if (data.testBit(1) and not si.last_out_port3.testBit(1)):
                    discard playChannel(-1, si.sounds[SHOOT_LASER_SND], 0)
                if (data.testBit(2) and not si.last_out_port3.testBit(2)):
                    discard playChannel(-1, si.sounds[PLAYER_DEATH_SND], 0)
                if (data.testBit(3) and not si.last_out_port3.testBit(3)):
                    discard playChannel(-1, si.sounds[INVADER_DEATH_SND], 0)
                if (data.testBit(4) and not si.last_out_port3.testBit(4)):
                    discard playChannel(-1, si.sounds[EXTRA_LIFE_SND], 0)
                
                si.last_out_port3 = data
        of 2:
            if data != si.last_out_port5:
                if (data.testBit(0) and not si.last_out_port5.testBit(0)):
                    discard playChannel(-1, si.sounds[FLEET1_SND], 0)
                if (data.testBit(1) and not si.last_out_port5.testBit(1)):
                    discard playChannel(-1, si.sounds[FLEET2_SND], 0)
                if (data.testBit(2) and not si.last_out_port5.testBit(2)):
                    discard playChannel(-1, si.sounds[FLEET3_SND], 0)
                if (data.testBit(3) and not si.last_out_port5.testBit(3)):
                    discard playChannel(-1, si.sounds[FLEET4_SND], 0)
                if (data.testBit(4) and not si.last_out_port5.testBit(4)):
                    discard haltChannel(ufo_move_channel)
                    discard playChannel(-1, si.sounds[UFO_HIT_SND], 0)
                
                si.last_out_port5 = data
        else:
            discard

proc get_color(px, py: int): tuple[r, g, b: byte] =
    # the screen is 256 * 224 pixels, and is rotated anti-clockwise.
    # these are the overlay dimensions:
    # ,_______________________________.
    # |WHITE            ^             |
    # |                32             |
    # |                 v             |
    # |-------------------------------|
    # |RED              ^             |
    # |                32             |
    # |                 v             |
    # |-------------------------------|
    # |WHITE                          |
    # |         < 224 >               |
    # |                               |
    # |                 ^             |
    # |                120            |
    # |                 v             |
    # |                               |
    # |                               |
    # |                               |
    # |-------------------------------|
    # |GREEN                          |
    # | ^                  ^          |
    # |56        ^        56          |
    # | v       72         v          |
    # |____      v      ______________|
    # |  ^  |          | ^            |
    # |<16> |  < 118 > |16   < 122 >  |
    # |  v  |          | v            |
    # |WHITE|          |         WHITE|
    # `-------------------------------'

    case px:
        of 0 .. pred(16):
            case py:
                of 16 .. pred(16 + 118):
                    result = (r: 0'u8, g: 255'u8, b: 0'u8) # Green
                else:
                    result = (r: 255'u8, g: 255'u8, b: 255'u8) # White
        of 16 .. pred(16 + 56):
            result = (r: 0'u8, g: 255'u8, b: 0'u8) # Green
        of (16 + 56 + 120) .. pred(16 + 56 + 120 + 32):
            result = (r: 255'u8, g: 0'u8, b: 0'u8) # Red
        else:
            result = (r: 255'u8, g: 255'u8, b: 255'u8) # White


# updates the screen buffer in accordance with the VRAM
proc updateScreen(si: var Invaders) =
    for i in 0 ..< (SCREEN_HEIGHT * SCREEN_WIDTH div 8):
        let
            y = i * 8 div SCREEN_HEIGHT
            base_x = (i * 8) mod SCREEN_HEIGHT
            curr_byte = si.memory[VRAM_ADDR + i]

        for bit in 0..7:
            var
                px = base_x + bit
                py = y
                r: byte = 0
                g: byte = 0
                b: byte = 0

            let is_pixel_lit = curr_byte.testBit(bit)

            if is_pixel_lit:
                if not si.colored_screen:
                    (r, g, b) = (255.byte, 255.byte, 255.byte)
                else:
                    (r, g, b) = get_color(px, py)

            let tx = px
            px = py
            py = SCREEN_HEIGHT - tx - 1

            si.screen_buffer[py][px][0] = r
            si.screen_buffer[py][px][1] = g
            si.screen_buffer[py][px][2] = b

    si.updateTexture(si)


proc update*(si: var Invaders, ms: int) =
    var count = 0

    while count < (ms*CLOCK_SPEED div 1000):
        var cyc = si.cpu.cycles
        # echo si.cpu.PC
        si.cpu.step()
        var elapsed = si.cpu.cycles - cyc
        count += elapsed

        #interrupt handling
        if si.cpu.cycles >= (CYCLES_PER_FRAME div 2):
            si.cpu.cycles -= CYCLES_PER_FRAME div 2

            si.cpu.interrupt(si.next_interrupt)

            if(si.next_interrupt == 0xD7):
                si.updateScreen()

            si.next_interrupt = if (si.next_interrupt == 0xCF): 0xD7 else: 0xCF



