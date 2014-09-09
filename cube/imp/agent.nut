function accelDataEventHandler(data) {
    server.log(format("Agent received: x = %.02f, y = %.02f, z = %.02f", data.x, data.y, data.z));
}

device.on("accelDataEvent", accelDataEventHandler);
