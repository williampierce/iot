/******************** APPLICATION CODE ********************/
const IMP_ONLY = 0;
const ACCEL_THRESHOLD = 0.8
const LED_COUNT = 3;
const CUBE_SERVER = "http://67.180.197.235:8765";

// === Upstream ===
// *** Device to Agent ***

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

function AccelDataEventHandler(data)
{
    local face = AccelDataToTopFace(data);
    server.log(format("Agent received: x = %.02f, y = %.02f, z = %.02f ==> face = %i", data.x, data.y, data.z, face));
    
    if(IMP_ONLY)
        lightDeviceFace(face);
    else
        publishDeviceOrientation(face);
}

device.on("accelDataEvent", AccelDataEventHandler);


// *** Agent to Server ***

function processPostResponse(response) 
{
    server.log("Code: " + response.statuscode + ". Body: " + response.body);
}
 
// Support for publishing
function processGetResponse(resp)
{
    //server.log("Code: " + response.statuscode);
    local err  = null;
    local data = null;
    
    if (resp.statuscode != 200) {
        err = format("%i - %s", resp.statuscode, resp.body);
    } else {
        try {        
            //data = http.jsondecode(resp.body);
            server.log("Response:");
            server.log(resp.body);
        } catch (ex) {
            err = ex;
            server.log("jsondecode error: " + ex);
        }
    }
}

function publishStateWithPost(face_number) 
{    
    // Prepare the request with a JSON payload
    local body = http.jsonencode({ face = face_number });
    local extraHeaders = {};
    local request = http.post(CUBE_SERVER + "/report_state", extraHeaders, body);

    request.sendasync(processPostResponse);
}

function publishStateWithGet(face)
{
    local extraHeaders = {};
    local request = http.get(CUBE_SERVER + "/ping", extraHeaders);
    
    server.log("Sending http request...");
    request.sendasync(processGetResponse);
}
 

function publishDeviceOrientation(face)
{
    //publishStateWithGet(face);
    publishStateWithPost(face);
}

// === Downstream ===
// *** Server to Agent ***

function httpRequestHandler(request, response) {
    server.log(request.method);
    server.log(request.path);
    server.log(request.query);
    server.log(request.headers);
    //server.log(request.body);
    
    local state_table = http.jsondecode(request.body);
    foreach(key, value in state_table)
    {
        server.log("Entry: " + key + " -> " + value);
    }
    
    if("face" in state_table)
    {
        lightDeviceFace(state_table["face"].tointeger());
    }
    
    // send a response back to whoever made the request
    response.send(200, "OK");
}
 
// your agent code should only ever have ONE http.onrequest call.
http.onrequest(httpRequestHandler);


// *** Agent to Device ***

function lightDeviceLeds(led_select_array)
{
    try
    {
        device.send("ledControlEvent", led_select_array);
    }
    catch(ex)
    {
        server.log("Error - " + ex);
    }
}

// Support for Imp-only version (useful for sanity checking)
// Send a command to light the top face LED and turn off the others.
function lightDeviceFace(face)
{
    server.log("Lighting device face " + face);
    local face_to_led_map = [-1,  // unknown
                             -1,  // top
                             -1,  // north
                              2,  // east
                              1,  // south
                              0,  // west
                             -1]; // bottom
    
    // Currently, cube has 3 LEDs, on the east (3), south (4), and west (5) faces.
    // These LEDs have position 2, 1, and 0, respectively in the LED array.
    
    local led_select_array = array(LED_COUNT, 0);
    if(3 <= face && face <= 5)
    {
        local led = face_to_led_map[face];
        led_select_array[led] = 1;
    }
    
    lightDeviceLeds(led_select_array);
}
