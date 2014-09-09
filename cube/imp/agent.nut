// Read the x/y/z accelerations from the device. Determine if one of the three faces with an LED is
// up. Send a command to light the LED for the top face, and turn off the others.

const accelThreshold = 0.7
const LED_COUNT = 3;
local ledSelectArray = array(LED_COUNT);

ledSelectArray[0] = 0;
ledSelectArray[1] = 1;
ledSelectArray[2] = 1;

function updateLedSelect(data)
{
    ledSelectArray[0] = data.x < -accelThreshold  ? 1 : 0;
    ledSelectArray[1] = data.y < -accelThreshold  ? 1 : 0;
    ledSelectArray[2] = data.x >  accelThreshold  ? 1 : 0;
}

function accelDataEventHandler(data)
{
    server.log(format("Agent received: x = %.02f, y = %.02f, z = %.02f", data.x, data.y, data.z));
    
    updateLedSelect(data);
    
    try
    {
        device.send("ledControlEvent", ledSelectArray);
    } catch(ex) {
            server.log("Error - " + ex);
    }
}

device.on("accelDataEvent", accelDataEventHandler);
