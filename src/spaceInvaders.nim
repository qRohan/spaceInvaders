import std/strformat
import std/bitops

import sdl2

import i8080/i8080

import ./machine

var si = newInvaders()

si.loadROM("roms/invaders.h", 0x0000)
si.loadROM("roms/invaders.g", 0x0800)
si.loadROM("roms/invaders.f", 0x1000)
si.loadROM("roms/invaders.e", 0x1800)

var
    window: WindowPtr
    texture: TexturePtr
    sdlr: SDL_Return
    e: Event

    last_time: uint32 = 0

    SCALE: cint = 2

sdlr = sdl2.init(INIT_EVERYTHING)
assert sdlr == SdlSuccess

window = createWindow("Space Invaders", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, SCREEN_WIDTH * SCALE, SCREEN_HEIGHT * SCALE, SDL_WINDOW_SHOWN)
assert not window.isNil

var renderer = window.createRenderer(-1, 0)
discard renderer.setLogicalSize(SCREEN_WIDTH, SCREEN_HEIGHT)

texture = createTexture(renderer, SDL_PIXELFORMAT_RGB24, SDL_TEXTUREACCESS_STREAMING, SCREEN_WIDTH, SCREEN_HEIGHT)
proc updateTexture(si: Invaders)
si.updateTexture = updateTexture

proc updateTexture(si: Invaders) =
    var
        pitch: cint = 0
        pixels: pointer 
    
    var sdlReturn  = texture.lockTexture(nil, pixels.addr, pitch.addr)
    assert sdlReturn == SdlSuccess, fmt"Unable to lock texture: {getError()}"
    copyMem(pixels, si.screen_buffer.unsafeAddr, pitch * SCREEN_HEIGHT)
    texture.unlockTexture()

proc handleKeyDown(si: Invaders, key: Scancode) =
    case key:
        of SDL_SCANCODE_C:
            si.port1.setBit(0)
        of SDL_SCANCODE_2:
            si.port1.setBit(1)
        of SDL_SCANCODE_1, SDL_SCANCODE_RETURN:
            si.port1.setBit(2)
        of SDL_SCANCODE_SPACE:
            si.port1.setBit(4)
            si.port2.setBit(4)
        of SDL_SCANCODE_LEFT:
            si.port1.setBit(5)
            si.port2.setBit(5)
        of SDL_SCANCODE_RIGHT:
            si.port1.setBit(6)
            si.port2.setBit(6)
        of SDL_SCANCODE_T:
            si.port2.setBit(2)
        of SDL_SCANCODE_K:
            si.colored_screen = not si.colored_screen
        else:
            discard

proc handleKeyUp(si: Invaders, key: Scancode) =
    case key:
        of SDL_SCANCODE_C:
            si.port1.clearBit(0)
        of SDL_SCANCODE_2:
            si.port1.clearBit(1)
        of SDL_SCANCODE_1, SDL_SCANCODE_RETURN:
            si.port1.clearBit(2)
        of SDL_SCANCODE_SPACE:
            si.port1.clearBit(4)
            si.port2.clearBit(4)
        of SDL_SCANCODE_LEFT:
            si.port1.clearBit(5)
            si.port2.clearBit(5)
        of SDL_SCANCODE_RIGHT:
            si.port1.clearBit(6)
            si.port2.clearBit(6)
        of SDL_SCANCODE_T:
            si.port2.clearBit(2)
        else:
            discard

proc mainLoop() = 
    var
        ctime = getTicks()
        dt = ctime - last_time

    while(pollEvent(e)):
        # echo e
        case e.kind:
            of QuitEvent:
                system.quit()
            of KeyDown:
                echo "keydown"
                handleKeyDown(si, e.key.keysym.scancode)
            of KeyUp:
                echo "keyup"
                handleKeyUp(si, e.key.keysym.scancode)
            else:
                discard
    si.update(dt.int)

    renderer.clear()
    renderer.copy(texture, nil, nil)
    renderer.present()

    last_time = ctime
    # echo dt


while(true):
    # discard pollEvent(e)
    # if e.kind == sdl2.QuitEvent:
    #         system.quit()
    # else:
    mainLoop()    


destroy window
destroy renderer