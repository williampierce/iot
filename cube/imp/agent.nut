/******************** APPLICATION CODE ********************/
const IMP_ONLY = 0;
const ACCEL_THRESHOLD = 0.8
const LED_COUNT = 3;
const CUBE_SERVER = "http://67.180.197.235:8765";

// === Upstream ===
// *** Device to Agent ***
//     Events
//         accel_evt: {dev_id, {x, y, z}}

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

function AccelDataEventHandler(accel_evt)
{
    local accel = accel_evt.accel;
    local face  = AccelDataToTopFace(accel);
    server.log(format("Evt from device %s: x = %.02f, y = %.02f, z = %.02f ==> face = %i",
        accel_evt.dev_id, accel.x, accel.y, accel.z, face));
    
    if(IMP_ONLY)
        lightDeviceFace(face);
    else
        publishDeviceOrientation(face);
}

device.on("accelDataEvent", AccelDataEventHandler);


// *** Agent to Server ***

function processPostResponse(response) 
{
    server.log("HTTP Response. Code: " + response.statuscode + ", Body: " + response.body);
}

// Support for publishing
function publishStateWithPost(faceId)
{    
    // Prepare the request with a JSON payload
    local agentUrl   = http.agenturl();
    local agentIdStr = split(agentUrl, "/").top();
    
    local url          = CUBE_SERVER + "/reportState";
    local extraHeaders = {};
    local body         = http.jsonencode({agentId = agentIdStr, face = faceId});
    
    server.log("Posting HTTP request...");
    server.log("    url:  " + url);
    server.log("    body: " + body);
    local request      = http.post(url, extraHeaders, body);

    request.sendasync(processPostResponse);
}

function publishDeviceOrientation(face)
{
    publishStateWithPost(face);
}

// === Downstream ===
// *** Server to Agent ***

function httpRequestHandler(request, response) {
    server.log(format("HTTP %s request for %s received...", request.method, request.path));
    // server.log(request.query);
    // server.log(request.headers);
    // server.log(request.body);
    
    // Todo: check path for "setState" request
    local bodyData = http.jsondecode(request.body);
    foreach(key, value in bodyData)
    {
        server.log("    body: " + key + " -> " + value);
    }
    
    if("face" in bodyData)
    {
        lightDeviceFace(bodyData["face"].tointeger());
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
