// MMA8452 Accelerometer
class MMA8452 {

    static DEFAULT_ADDR = 0x3A; // 0x1D << 1

    _i2c    = null;
    _addr   = null;
    _fs     = null;

    constructor(i2c, addr=null) {

        // Set the address or use the default
        if (addr) {
            _addr = addr;
        } else {
            _addr = DEFAULT_ADDR;
        }

        // Configure i2c
        _i2c = i2c;
        _i2c.configure(CLOCK_SPEED_400_KHZ);

        // Assume range is 2g at boot
        _fs = 2;

        _init();

    }

    function _init() {

        enum REGISTERS {
            STATUS          = "\x00",
            OUT_X_MSB       = "\x01",
            OUT_X_LSB       = "\x02",
            OUT_Y_MSB       = "\x03",
            OUT_Y_LSB       = "\x04",
            OUT_Z_MSB       = "\x05",
            OUT_Z_LSB       = "\x06",
            SYSMOD          = "\x0B",
            INT_SOURCE      = "\x0C",
            WHO_AM_I        = "\x0D",
            XYZ_DATA_CFG    = "\x0E",
            HP_FILTER_CUTOFF= "\x0F",
            PL_STATUS       = "\x10",
            PL_CFG          = "\x11",
            PL_COUNT        = "\x12",
            PL_BF_ZCOMP     = "\x13",
            P_L_THS_REG     = "\x14",
            FF_MT_CFG       = "\x15",
            FF_MT_SRC       = "\x16",
            FF_MT_THS       = "\x17",
            FF_MT_COUNT     = "\x18",
            TRANSIENT_CFG   = "\x1D",
            TRANSIENT_SRC   = "\x1E",
            TRANSIENT_THS   = "\x1F",
            TRANSIENT_COUNT = "\x20",
            PULSE_CFG       = "\x21",
            PULSE_SRC       = "\x22",
            PULSE_THSX      = "\x23",
            PULSE_THSY      = "\x24",
            PULSE_THSZ      = "\x25",
            PULSE_TMLT      = "\x26",
            PULSE_LTCY      = "\x27",
            PULSE_WIND      = "\x28",
            ASLP_COUNT      = "\x29",
            CTRL_REG1       = "\x2A",
            CTRL_REG2       = "\x2B",
            CTRL_REG3       = "\x2C",
            CTRL_REG4       = "\x2D",
            CTRL_REG5       = "\x2E",
            OFF_X           = "\x2F",
            OFF_Y           = "\x30",
            OFF_Z           = "\x31"
        }
    }

    function wake() {
        local reg = blob(1);
        reg.writestring(_i2c.read(_addr, REGISTERS.CTRL_REG1, 1));
        _i2c.write(_addr, format("%s%c", REGISTERS.CTRL_REG1, reg[0] | 0x01));
    }

    function sleep() {
        local reg = blob(1);
        reg.writestring(_i2c.read(_addr, REGISTERS.CTRL_REG1, 1));
        _i2c.write(_addr, format("%s%c", REGISTERS.CTRL_REG1, reg[0] & 0xFE));
    }

    function read() {
        // Reads the status register + 3x 2-byte data registers
        local reg = blob(7);
        reg.writestring(_i2c.read(_addr, REGISTERS.STATUS, 7));
        local data = {
            x = (reg[1] << 4) | (reg[2] >> 4),
            y = (reg[3] << 4) | (reg[4] >> 4),
            z = (reg[5] << 4) | (reg[6] >> 4)
        }
        // Convert from two's compliment
        if (data.x & 0x800) { data.x -= 0x1000; }
        if (data.y & 0x800) { data.y -= 0x1000; }
        if (data.z & 0x800) { data.z -= 0x1000; }
        // server.log(format("Status: 0x%02X", reg[0]));
        return data;
    }

    function readG() {
        local data = read();
        data.x = data.x * _fs / 2048.0;
        data.y = data.y * _fs / 2048.0;
        data.z = data.z * _fs / 2048.0;
        return data;
    }
}

/******************** APPLICATION CODE ********************/
const ACCEL_THRESHOLD = 0.8

// *** Upstream ***

// Use the x/y/z accelerations from the device to determine which face is up.
// Convention for numbering cube faces: If cube is in front of you and you're facing north, top=1, sides are 2..5,
// clockwise from north, and bottom=6. Unknown=0. If we orient the accelerometer so that the z axis points up, the
// x axis points to our right, and the y axis points the way we are facing, then we have the following correspondence
// between faces and x/y/z values:
//     Face 1:  z =  1
//          2:  y =  1
//          3:  x =  1
//          4:  y = -1
//          5:  x = -1
//          6:  z = -1
function AccelDataToTopFace(accel)
{
    local face = 0;

    if (accel.len() != 3)
        return face;
    
    if(accel.z >  ACCEL_THRESHOLD)
        face = 1;
    else if(accel.y >  ACCEL_THRESHOLD)
        face = 2;
    else if(accel.x >  ACCEL_THRESHOLD)
        face = 3;
    else if(accel.y < -ACCEL_THRESHOLD)
        face = 4;
    else if(accel.x < -ACCEL_THRESHOLD)
        face = 5;
    else if(accel.z < -ACCEL_THRESHOLD)
        face = 6;
    
    return face;
}

// Heartbeat function to check sensors and send update as necessary
local g_lastFace = 0;
local g_devId    = hardware.getdeviceid();

function heartBeat() {
    try
    {
        local accel_data = accel.readG();
        local face       = AccelDataToTopFace(accel_data);
    
        if(face != g_lastFace)
        {
            local topFaceEvent = {
                dev_id = g_devId,
                face   = face
            };
        
            agent.send("topFaceEvent", topFaceEvent);
            g_lastFace = face;
        }
    }
    catch(error)
    {
        // We occasionally see blob.writeString() errors from readG().
        server.log("Skipping update on exception: " + error);
    }
    imp.wakeup(2, heartBeat);
}

accel <- MMA8452(hardware.i2c89);
accel.wake();

server.log(format("Starting Cube Device..."));

heartBeat();


// *** Downstream ***
// LED control
const LED_COUNT = 3;
local led_array = array(LED_COUNT);

led_array[0] = hardware.pin2;
led_array[1] = hardware.pin5;
led_array[2] = hardware.pin7;

led_array[0].configure(DIGITAL_OUT);
led_array[1].configure(DIGITAL_OUT);
led_array[2].configure(DIGITAL_OUT);

function LedControlEventHandler(led_select_array)
{
    local ledStr = "";
    for (local led=0; led<led_select_array.len(); led++)
    {
        led_array[led].write(led_select_array[led]);
        ledStr += format(" %i", led_select_array[led]);
    }
    server.log("Device LED pattern: " + ledStr);
}

agent.on("ledControlEvent", LedControlEventHandler);
