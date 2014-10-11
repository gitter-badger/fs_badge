const max_log_items = 10;
local log_insert = 0;
local last_logs = array(max_log_items, "");

device.on("senddata", function(data) {
  // Set URL to your web service
  local url = "http://ataraxia.ericbetts.org:3000/electricimp/tagread";

  // Set Content-Type header to json
  local headers = { "Content-Type": "application/json"};

  // encode data and log
  local body = http.jsonencode(data);
  server.log(body);

  // send data to your web service
  http.post(url, headers, body).sendsync();
});

device.on("sendlog", function(log) {
  last_logs[log_insert++] = log;
  if (log_insert >= max_log_items) log_insert = 0;
});

http.onrequest(function(req, resp) {
  try {
    local content = "";
    // process incoming http request
    for (local i = 0; i < max_log_items && i < last_logs.len(); i++) {
      content += last_logs[i] + "\n<br/>";
    }

    // if everything worked as expected, send a 200 OK
    resp.send(200, content);
  }
  catch (ex) {
    // if an error occured, send a 500 Internal Server Error
    resp.send(500, "Internal Server Error: " + ex);
  }
});

// Basic wrapper to create an execute an HTTP POST
function HttpPostWrapper (url, headers, string) {
  local request = http.post(url, headers, string);
  local response = request.sendsync();
  return response;
}

device.send("debug", true);