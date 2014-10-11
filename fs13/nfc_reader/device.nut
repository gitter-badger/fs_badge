const PN532_PREAMBLE            = 0x00;
const PN532_STARTCODE2          = 0xFF;
const PN532_POSTAMBLE           = 0x00;

const PN532_HOSTTOPN532         = 0xD4;

const PN532_FIRMWAREVERSION     = 0x02;
const PN532_SAMCONFIGURATION    = 0x14;
const PN532_RFCONFIGURATION     = 0x32;

const PN532_SPI_STATREAD        = 0x02;
const PN532_SPI_DATAWRITE       = 0x01;
const PN532_SPI_DATAREAD        = 0x03;
const PN532_SPI_READY           = 0x01;

const PN532_MAX_RETRIES         = 0x05;

const RUNLOOP_INTERVAL          = 2;

const MIFARE_CMD_AUTH_A                   = 0x60;
const MIFARE_CMD_AUTH_B                   = 0x61;
const MIFARE_CMD_READ                     = 0x30;
const MIFARE_CMD_WRITE                    = 0xA0;
const MIFARE_CMD_TRANSFER                 = 0xB0;
const MIFARE_CMD_DECREMENT                = 0xC0;
const MIFARE_CMD_INCREMENT                = 0xC1;
const MIFARE_CMD_STORE                    = 0xC2;


const DESFIRE_GETAPPLICATIONIDS = 0x6A
const DESFIRE_SELECTAPPLICATION = 0x5A
const DESFIRE_GETFILEIDS = 0x6F
const DESFIRE_GETFILESETTINGS = 0xF5
const DESFIRE_READDATA = 0xBD

local pn532_ack = [0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00];
local pn532_firmware_version = [0x00, 0xFF, 0x06, 0xFA, 0xD5, 0x03];

local response_buffer = blob(96);
local nfc_booted = true;
local DEBUG = false;

local response_start = 8;//Desfire
const DESFIRE_STATUS_BYTE = 8;
const EOF = 0x00;

const PN532_COMMAND_INDATAEXCHANGE = 0x40;

//All these are 6 bytes further than expected
const TARGET_COUNT_OFFSET       = 7;
const SENS_RES_OFFSET           = 9;//and 10
const SEL_RES_OFFSET            = 11;
const TAGID_LENGTH_OFFSET       = 12;

///////////////////////////////////////
// NFC SPI Functions
function spi_init() {
  // Configure SPI_257 at about 4MHz
  hardware.configure(SPI_257);
  hardware.spi257.configure(LSB_FIRST | CLOCK_IDLE_HIGH, 500);

  hardware.pin1.configure(DIGITAL_OUT); // Configure the chip select pin
  hardware.pin1.write(1);               // pull CS high
  imp.sleep(0.1);                       // wait 100 ms
  hardware.pin1.write(0);               // pull CS low to start the transmission of data
  imp.sleep(0.1);
  log("SPI Init successful");
}

function spi_read_ack() {
  spi_read_data(6);
  for (local i = 0; i < 6; i++) {
    if (response_buffer[i] != pn532_ack[i])
      return false;
  }
  return true;
}

function spi_read_data(length) {
  hardware.pin1.write(0); // pull CS low
  imp.sleep(0.002);
  spi_write(PN532_SPI_DATAREAD); // read leading byte DR and discard

  local response = "";
  for (local i = 0; i < length; i++) {
    imp.sleep(0.001);
    response_buffer[i] = spi_write(PN532_SPI_STATREAD);
    response = response + format("%02x", response_buffer[i]) + " ";
  }

  //log("spi_read_data: " + response);
  hardware.pin1.write(1); // pull CS high
}

function spi_read_status() {
  hardware.pin1.write(0); // pull CS low
  imp.sleep(0.002);

  // Send status command to PN532; ignore returned byte
  spi_write(PN532_SPI_STATREAD);

  // Collect status response, send junk 0x00 byte
  local value = spi_write(0x00);
  hardware.pin1.write(1); // pull CS high

  return value;
}

function spi_write_command(cmd, cmdlen) {
    local checksum;
    hardware.pin1.write(0); // pull CS low
    imp.sleep(0.002);
    cmdlen++;

    spi_write(PN532_SPI_DATAWRITE);

    checksum = PN532_PREAMBLE + PN532_PREAMBLE + PN532_STARTCODE2;
    spi_write(PN532_PREAMBLE);
    spi_write(PN532_PREAMBLE);
    spi_write(PN532_STARTCODE2);

    spi_write(cmdlen);
    local cmdlen_1=256-cmdlen;
    spi_write(cmdlen_1);

    spi_write(PN532_HOSTTOPN532);
    checksum += PN532_HOSTTOPN532;

    for (local i = 0; i < cmdlen - 1; i++) {
        spi_write(cmd[i]);
        checksum += cmd[i];
    }

    checksum %= 256;
    local checksum_1 = 255 - checksum;
    spi_write(checksum_1);
    spi_write(PN532_POSTAMBLE);

    hardware.pin1.write(1); // pull CS high
}

function spi_write(byte) {
    // Write the single byte
    hardware.spi257.write(format("%c", byte));

    // Collect the response from the holding register
    local resp = hardware.spi257.read(1);

    // Show what we sent
    //log(format("SPI tx %02x, rx %02x", byte, resp[0]));

    // Return the byte
    return resp[0];
}

////////////////////////////////////
// PN532 functions
function nfc_init() {
    hardware.pin1.write(0); // pull CS low
    imp.sleep(1);

    /* No need for this at the moment but it's useful for debugging.
    if (!nfc_get_firmware_version()) {
        error("Didn't find PN53x board");
        nfc_booted = false;
    }
    */

    if (!nfc_SAM_config()) {
        error("SAM config error");
      nfc_booted = false;
    }
}

function nfc_get_firmware_version() {
  log("Getting firmware version");

  if (!send_command_check_ready([PN532_FIRMWAREVERSION], 1,100))
      return 0;
  spi_read_data(12);

  for (local i = 0; i < 6; i++) {
      if (response_buffer[i] != pn532_firmware_version[i])
          return false;
  }

  log(format("Found chip PN5%02x", response_buffer[6]));
  log("Firmware ver "+ response_buffer[7] + "." + response_buffer[8]);
  log(format("Supports %02x", response_buffer[9]));

  return true;
}

function nfc_SAM_config() {
  log("SAM configuration");
  if (!send_command_check_ready([PN532_SAMCONFIGURATION, 0x01, 0x14, 0x01], 4, 100))
      return false;

  spi_read_data(8);
  if (response_buffer[5] == 0x15) return true;
  else return false;
}

function nfc_scan() {
    //log("nfc_p2p_scan");
    send_command_check_ready([PN532_RFCONFIGURATION, PN532_MAX_RETRIES, 0xFF, 0x01, 0x14], 5, 100);
    if (!send_command_check_ready([
        0x4A,                // InListPassivTargets
        0x01,                // Number of cards to init (if in field)
        0x00,                // Baud rate (106kbit/s)
        ], 3, 100)) {
        error("Unknown error detected during nfc_p2p_scan");
        return false;
    }
    spi_read_data(32);

    local target_count = response_buffer[TARGET_COUNT_OFFSET];
    local SENS_RES = response_buffer[SENS_RES_OFFSET] + response_buffer[SENS_RES_OFFSET+1] * 255;
    local SEL_RES = response_buffer[SEL_RES_OFFSET];
    local length = response_buffer[TAGID_LENGTH_OFFSET];

    if (target_count > 0) {
      flash_leds_for_tag();
      //http://www.proxmark.org/files/Documents/NFC/ACS_API_ACR122.pdf
      //
      //Tip: The tag type can be determined by recognizing the SEL_RES.
      //SEL_RES of some common tag types.
      const MIFARE_Ultralight = 0x00;
      const MIFARE_1K = 0x08;
      const MIFARE_MINI = 0x09;
      const MIFARE_4K = 0x18
      const MIFARE_DESFIRE = 0x20;
      const JCOP30 = 0x28;
      const Gemplus_MPCOS = 0x98


        local tagid = "";
        for (local i = 0; i < length; i++) {
          tagid = tagid + format("%02x", response_buffer[TAGID_LENGTH_OFFSET+1+i]);
        }

        log(format("count: %i, SENS_RES: %02x SEL_RES: %02x tag_len: %i, tag_id:%s", target_count, SENS_RES, SEL_RES, length, tagid));

        if(SEL_RES == MIFARE_1K) {
          response_buffer.seek(TAGID_LENGTH_OFFSET+1)
          read_mfc_data(response_buffer.readblob(length));
        } else if (SEL_RES == MIFARE_Ultralight) {
          response_buffer.seek(TAGID_LENGTH_OFFSET+1)
          read_mul_data(response_buffer.readblob(length));
        } else if (SEL_RES == MIFARE_DESFIRE) {
          response_buffer.seek(TAGID_LENGTH_OFFSET+1)
          read_desfire_data(response_buffer.readblob(length));
        }
        return true;
    } else {
      log(format("No targets found"));
    }

    return false;
}

function GetApplicationIDs() {
  local debug = "";

  if (!send_command_check_ready([
    PN532_COMMAND_INDATAEXCHANGE,
    0x01,
    DESFIRE_GETAPPLICATIONIDS
    ], 3, 100)) {
    error("Unknown error detected during PN532_COMMAND_INDATAEXCHANGE");
    return false;
  }
  spi_read_data(26);


  for (local j = DESFIRE_STATUS_BYTE; j < 16; j++) {
    debug = debug + format("%02x ", response_buffer[j]);
  }
  log(format("[GetApplicationIDs] %s", debug));

  if (response_buffer[DESFIRE_STATUS_BYTE] > 0) {
    //byte 8 is the first byte of the desfire protocol; status byte
    error("Last command returned non-0 status");
    return false;
  }

  //Status byte is followed by sets of 3 byte app ids
  response_buffer.seek(DESFIRE_STATUS_BYTE+1);
  local app_id = response_buffer.readblob(3);

  log(format("[GetApplicationIDs] %02x%02x%02x", app_id[0], app_id[1], app_id[2]));
  return true;

}

function SelectApplication(app_id) {
  local debug = "";
  if (!send_command_check_ready([
    PN532_COMMAND_INDATAEXCHANGE,
    0x01,
    DESFIRE_SELECTAPPLICATION,
    app_id[0],
    app_id[1],
    app_id[2]
    ], 6, 100)) {
    error("Unknown error detected during PN532_COMMAND_INDATAEXCHANGE");
    return false;
  }
  spi_read_data(26);

  for (local j = response_start; j < 16; j++) {
    debug = debug + format("%02x ", response_buffer[j]);
  }
  log(format("[SelectApplication] %s", debug));

  if (response_buffer[DESFIRE_STATUS_BYTE] > 0) {
    //byte 8 is the first byte of the desfire protocol; status byte
    error("Last command returned non-0 status");
    return false;
  }
  return true;
}

function GetFileIDs() {
  local files = blob(16);

  if (!send_command_check_ready([
    PN532_COMMAND_INDATAEXCHANGE,
    0x01,
    DESFIRE_GETFILEIDS
    ], 3, 100)) {
    error("Unknown error detected during PN532_COMMAND_INDATAEXCHANGE");
    return false;
  }
  spi_read_data(26);
  local debug = "";
  for (local j = DESFIRE_STATUS_BYTE; j < (DESFIRE_STATUS_BYTE+16); j++) {
    debug = debug + format("%02x ", response_buffer[j]);
  }
  //log(format("[GetFileIDs] %s", debug));

  if (response_buffer[DESFIRE_STATUS_BYTE] > 0) {
    //byte 8 is the first byte of the desfire protocol; status byte
    error("Last command returned non-0 status");
    return false;
  }

  //Status byte is followed by up to 16 file IDs
  local max_count = 16;
  local file_count = 0;
  for (file_count = 0; response_buffer[DESFIRE_STATUS_BYTE + file_count + 1] != EOF && file_count < max_count; file_count++);
  file_count--;//remove value preceeding 0x00

  response_buffer.seek(DESFIRE_STATUS_BYTE+1)
  files = response_buffer.readblob(file_count);

  log(format("[GetFileIDs] count: %i", files.len()));

  local index = 0;
  do {
    local rtn = true;
    local fileno = files[index];
    local type = GetFileSettings(fileno);

    log(format("[GetFileIDs] Reading index:%i fileno:%i type:%i", index, fileno, type));
    if (type == 0 || type == 1) {
      rtn = ReadData(fileno, 0, 0);
      if (!rtn) return rtn;
    }

    index++;
  } while(index < file_count)

  return true;
}

function GetFileSettings(fileno) {

  if (!send_command_check_ready([
    PN532_COMMAND_INDATAEXCHANGE,
    0x01,
    DESFIRE_GETFILESETTINGS,
    fileno
    ], 4, 100)) {
    error("Unknown error detected during PN532_COMMAND_INDATAEXCHANGE");
    return false;
  }
  spi_read_data(26);
  local debug = "";
  for (local j = DESFIRE_STATUS_BYTE; j < 16; j++) {
    debug = debug + format("%02x ", response_buffer[j]);
  }
  //log(format("[GetFileSettings] %s", debug));

  /*
    First byte is file type:
    Standard Data Files (coded as 0x00)
    Backup Data Files (coded as 0x01)
    Value Files with Backup (coded as 0x02)
    Linear Record Files with Backup (coded as 0x03)
    Cyclic Record Files with Backup (coded as 0x04)

    second byte is encryption.  0 = plain, 1 = secured, 3 = enciphered
  */

  if (response_buffer[DESFIRE_STATUS_BYTE] > 0) {
    //byte 8 is the first byte of the desfire protocol; status byte
    error("Last command returned non-0 status");
    return false;
  }

  return response_buffer[DESFIRE_STATUS_BYTE+1];
}

function ReadData(FileNo, Offset, Length) {
  local filecontents = blob(0);

  if (!send_command_check_ready([
    PN532_COMMAND_INDATAEXCHANGE,
    0x01,
    DESFIRE_READDATA,//ReadData(FileNo,Offset,Length)
    FileNo,
    0,0,0, //offset
    0,0,0 //length
    ], 10, 100)) {
    error("Unknown error detected during PN532_COMMAND_INDATAEXCHANGE");
    return false;
  }
  spi_read_data(96);

  if (response_buffer[DESFIRE_STATUS_BYTE] > 0 && response_buffer[DESFIRE_STATUS_BYTE] != 0xAF) { //0xAF means "incomplete content"
    //byte 8 is the first byte of the desfire protocol; status byte
    error("Last command returned non-0/0xAF status");
    return false;
  }

  do {
    local nextByte = DESFIRE_STATUS_BYTE + 1;
    local max_count = 59;

    do {
      filecontents.writen(response_buffer[nextByte], 'b');
      nextByte += 1;
      //log(format("[ReadData loop] nextByte: %i [%s]", nextByte, hexdump(response_buffer[nextByte])));
    } while(nextByte < (max_count + DESFIRE_STATUS_BYTE) && response_buffer[nextByte] != EOF)

    if (response_buffer[DESFIRE_STATUS_BYTE] == 0x00) break; //EOF

    //log(format("[ReadData] send continue command (0xAF)"));

    //Send command to continue file
    if (!send_command_check_ready([
      PN532_COMMAND_INDATAEXCHANGE,
      0x01,
      0xAF,
      ], 3, 100)) {
      error("Unknown error detected during PN532_COMMAND_INDATAEXCHANGE");
      return false;
    }
    spi_read_data(96);

  } while (response_buffer[DESFIRE_STATUS_BYTE] == 0xAF || response_buffer[DESFIRE_STATUS_BYTE] == 0x00);

  log(format("[ReadData] contents: %s[%i]", hexdump(filecontents), filecontents.len()));

  return true;
}

function hexdump(blobby) {
  local dump = "";
  for (local i = 0; i < blobby.len(); i++) {
    dump = dump + format("%02x ", blobby[i]);
  }
  return dump;
}

function asciidump(char) {
  if ((char > 0x1f) && (char < 0x7e)) {
    return format("%c", char);
  }
  return ".";
}

function read_desfire_data(tagid) {
  log("read_desfire_data");
  local rtn = true;

  rtn = GetApplicationIDs();
  if (!rtn) return;

  //Clipper card appid = 0x9011F2
  local app_id = [0x90, 0x11, 0xF2];

  rtn = SelectApplication(app_id);
  if (!rtn) return;

  rtn = GetFileIDs();
  if (!rtn) return;

  return true;
}//end desfire data

function read_mfc_data(tagid) {
  log(format("read_mfc_data"));
  local keyNumber = false;
  local data = blob(16*64);
  local resp_string = "";
  local keyCmd = (keyNumber) ? MIFARE_CMD_AUTH_A : MIFARE_CMD_AUTH_B;;
  local key = array(6, 0xFF);
  local i = 0;
  local next_loc = 0;
  for (i = 3; i < 64; i++) {//skip first few sectors before ndef data

    //Auth
    if (!send_command_check_ready([
      PN532_COMMAND_INDATAEXCHANGE,
      0x01,
      keyCmd,
      i,
      key[0], key[1], key[2], key[3], key[4], key[5],
      tagid[0], tagid[1], tagid[2], tagid[3]
      ], 4 + key.len() + tagid.len(), 100)) {
      error("Unknown error detected during PN532_COMMAND_INDATAEXCHANGE");
      return false;
    }
    spi_read_data(12);

    // check if the response is valid and we are authenticated???
    // for an auth success it should be bytes 5-7: 0xD5 0x41 0x00
    // Mifare auth error is technically byte 7: 0x14 but anything other and 0x00 is not good
    if (response_buffer[6] != 0x41 || response_buffer[7] != 0) { break; }

    //Read block of data
    if (!send_command_check_ready([
      PN532_COMMAND_INDATAEXCHANGE,
      0x01,
      MIFARE_CMD_READ,
      i
      ], 4, 100)) {
      error("Unknown error detected during PN532_COMMAND_INDATAEXCHANGE");
      return false;
    }
    spi_read_data(26);

    local trailing_block = ((i + 1) % 4 == 0);

    //back to real stuff
    if (response_buffer[6] == 0x41 && response_buffer[7] == 0) {
      if(!trailing_block) {
        for (local j = 0; j < 16; j++) {
          data[next_loc++] = response_buffer[j+8];
        }
      }
    } else {
      local debug = "";
      for (local j = 0; j < 16; j++) {
        debug = debug + format("%02x ", response_buffer[j]);
      }
      log("[BAD]" + debug);
      break;
    }

  }

  local skip_bytes = 2; //derives expirimentally
  if(data[skip_bytes] == 0x03) { //ndef message
    local len = data[skip_bytes+1];
    log(format("NDEF message, length %i", len));
    data.seek(skip_bytes+2);
    parse_ndef(tagid, data.readblob(len));
  } else {
    local debug = "";
    for (local j = skip_bytes; j < next_loc; j++) {
      debug = debug + format("%02x ", data[j]);
    }
    log(format("Not NDEF message %s", debug));
  }

}

function read_mul_data(tagid) {
  log("Staring read_mul_data");
  local response_bytes = blob(4*64);
  local resp_string = "";
  local i = 0;
  for (i = 0; i < 64; i++) {
    if (!send_command_check_ready([
      PN532_COMMAND_INDATAEXCHANGE,
      0x01,
      0x30,
      i,
      ], 4, 100)) {
      error("Unknown error detected during PN532_COMMAND_INDATAEXCHANGE");
      return false;
    }
    spi_read_data(26);

    //back to real stuff
    if (response_buffer[7] == 0) {
      for (local j = 8; j < 12; j++) {
        local next_loc = (j-8)+(i*4);
        response_bytes[next_loc] = response_buffer[j];
      }
    } else {
      //Logging
      local debug = "";
      for (local j = 0; j < 16; j++) {
        debug = debug + format("%02x ", response_buffer[j]);
      }
      log("[BAD]" + debug);
      break;
    }
  }
  log("completed loop to read data");

  local skip_bytes = 16; //Skip 16 bytes of MiFare data (MF0ICU1 p11 section 8.5)
  if(response_bytes[skip_bytes] == 0x03) { //ndef message
    local len = response_bytes[skip_bytes+1];
    log(format("NDEF message, length %i", len));
    response_bytes.seek(skip_bytes+2);
    parse_ndef(tagid, response_bytes.readblob(len));
  } else {
    local debug = "";
    for (local j = 0; j < 24; j++) {
      debug = debug + format("%02x ", response_bytes[j]);
    }
    log(format("Not NDEF message %s", debug));
  }

}

function parse_ndef(tagid, ndef_msg) {
  //Useful debugging line
  //log(format("ndef_msg: %s, offset: %i, data: %i", ndef_msg.tostring(), offset, idLength));
  log(format("ndef_msg length: %i, first byte %x", ndef_msg.len(), ndef_msg[0]));
  /* analyze the header field */
  local offset = 0;
  local me;

  do {
    local mb = ((ndef_msg[offset]) & 0x80) == 0x80;    /* Message Begin */
    me = ((ndef_msg[offset]) & 0x40) == 0x40; /* Message End */
    local cf = ((ndef_msg[offset]) & 0x20) == 0x20;    /* Chunk Flag */
    local sr = ((ndef_msg[offset]) & 0x10) == 0x10;    /* Short Record */
    local il = ((ndef_msg[offset]) & 0x8) == 0x8;  /* ID Length Present */
    local typeNameFormat = type_name_format((ndef_msg[offset]) & 0x07);
    offset++;

    log(format("MB=%s ME=%s CF=%s SR=%s IL=%s TNF=%s", mb.tostring(), me.tostring(), cf.tostring(), sr.tostring(), il.tostring(), typeNameFormat));

    if (cf) {
        log("chunk flag not supported yet\n");
        return 0;
    }

    local typeLength = ndef_msg[offset];
    offset++;

    local payloadLength = 0;
    if (sr) {
        payloadLength = ndef_msg[offset];
        payloadLength = (payloadLength < 0) ? payloadLength + 256 : payloadLength;
        offset++;
    } else {
      payloadLength = ndef_msg.readn('i');
      offset += 4;
    }

    local idLength = 0;
    if (il) {
        idLength = ndef_msg[offset];
        offset++;
    }

    ndef_msg.seek(offset);
    local type = ndef_msg.readblob(typeLength).tostring();

    offset += typeLength;


    local id;
    if (il) {
        ndef_msg.seek(offset);
        id = ndef_msg.readblob(idLength);
        offset += idLength;
    }
    log(format("typeLength=%i payloadLength=%i idLength=%i type=%s", typeLength, payloadLength, idLength, type.tostring()));

    ndef_msg.seek(offset);
    local payload = ndef_msg.readblob(payloadLength);
    offset += payloadLength;

    if (type[0] == 0x55 /*"U"*/) {
        /* handle URI case */
        local uri = ndef_parse_uri(payload, payloadLength);
        log(format("URI=%s", uri));
        agent.send("senddata", {"tagid": tagid, "url": uri});
    } else {
        log(format("unsupported NDEF record type: %02x", type[0]));
        return 0;
    }


  } while (!me);      /* as long as this is not the last record */
}

function ndef_parse_uri(payload, payload_len) {
    local prefix = uri_identifier_code(payload.readn('b'));
    local url = prefix + payload.readblob(payload_len).tostring();
    return url;
}

function type_name_format(b) {
  switch (b) {
    case 0x00:
  return "Empty";
    case 0x01:
  return "NFC Forum well-known type [NFC RTD]";
    case 0x02:
  return "Media-type as defined in RFC 2046 [RFC 2046]";
    case 0x03:
  return "Absolute URI as defined in RFC 3986 [RFC 3986]";
    case 0x04:
  return "NFC Forum external type [NFC RTD]";
    case 0x05:
  return "Unknown";
    case 0x06:
  return "Unchanged";
    case 0x07:
  return "Reserved";
    default:
  return "Invalid TNF byte!";
    }
}

function uri_identifier_code(b) {
    /*
     * Section 3.2.2 "URI Identifier Code" of "URI Record Type Definition
     * Technical Specification"
     */
    switch (b) {
    case 0x00:
  return "";
    case 0x01:
  return "http://www.";
    case 0x02:
  return "https://www.";
    case 0x03:
  return "http://";
    case 0x04:
  return "https://";
    case 0x05:
  return "tel:";
    case 0x06:
  return "mailto:";
    case 0x07:
  return "ftp://anonymous:anonymous@";
    case 0x08:
  return "ftp://ftp.";
    case 0x09:
  return "ftps://";
    case 0x0A:
  return "sftp://";
    case 0x0B:
  return "smb://";
    case 0x0C:
  return "nfs://";
    case 0x0D:
  return "ftp://";
    case 0x0E:
  return "dav://";
    case 0x0F:
  return "news:";
    case 0x10:
  return "telnet://";
    case 0x11:
  return "imap:";
    case 0x12:
  return "rtsp://";
    case 0x13:
  return "urn:";
    case 0x14:
  return "pop:";
    case 0x15:
  return "sip:";
    case 0x16:
  return "sips:";
    case 0x17:
  return "tftp:";
    case 0x18:
  return "btspp://";
    case 0x19:
  return "btl2cap://";
    case 0x1A:
  return "btgoep://";
    case 0x1B:
  return "tcpobex://";
    case 0x1C:
  return "irdaobex://";
    case 0x1D:
  return "file://";
    case 0x1E:
  return "urn:epc:id:";
    case 0x1F:
  return "urn:epc:tag:";
    case 0x20:
  return "urn:epc:pat:";
    case 0x21:
  return "urn:epc:raw:";
    case 0x22:
  return "urn:epc:";
    case 0x23:
  return "urn:nfc:";
    default:
  return "RFU";
    }
}

function nfc_power_down() {
    log("nfc_power_down");
    if (!send_command_check_ready([
        0x16,                // PowerDown
        0x20,                // Only wake on SPI
        ], 2, 100)) {
        error("Unknown error detected during nfc_power_down");
        return false;
    }

    spi_read_data(9);
}

// This command configures the NFC chip to act as a target, much like a standard
// dumb prox card.  The ID sent depends on the baud rate.  We're using 106kbit/s
// so the NFCID1 will be sent (3 bytes).
function nfc_p2p_target() {
    //log("nfc_p2p_target");
    if (!send_command([
        0x8C,                                   // TgInitAsTarget
        0x00,                                   // Accepted modes, 0 = all
        0x08, 0x00,                             // SENS_RES
        device_id_a, device_id_b, device_id_c,  // NFCID1
        0x40,                                   // SEL_RES
        0x01, 0xFE, 0xA2, 0xA3,                 // Parameters to build POL_RES (16 bytes)
        0xA4, 0xA5, 0xA6, 0xA7,
        0xC0, 0xC1, 0xC2, 0xC3,
        0xC4, 0xC5, 0xC6, 0xC7,
        0xFF, 0xFF,
        0xAA, 0x99, 0x88, 0x77,                 // NFCID3t
        0x66, 0x55, 0x44, 0x33,
        0x22, 0x11,
        0x00,                                   // General bytes
        0x00                                    // historical bytes
        ], 38, 100)) {
        error("Unknown error detected during nfc_p2p_target");
        return false;
    }
}

function send_command_check_ready(cmd, cmdlen, timeout) {
    return send_command(cmd, cmdlen, timeout) && check_ready(timeout);
}

function send_command(cmd, cmdlen, timeout) {
    local timer = 0;
    spi_write_command(cmd, cmdlen);

    // Wait for chip to say its ready!
    while (spi_read_status() != PN532_SPI_READY) {
        if (timeout != 0) {
            timer += 10;
            if (timer > timeout) {
                error("No response READY");
                return false;
            }
        }
        imp.sleep(0.01);
    }

    // read acknowledgement
    if (!spi_read_ack()) {
        error("Wrong ACK");
        return false;
    }

    //log("read ack");
    return true;
}

function check_ready(timeout) {
    local timer = 0;

    // Wait for chip to say its ready!
    while (spi_read_status() != PN532_SPI_READY) {
        if (timeout != 0) {
            timer += 10;
            if (timer > timeout) {
                error("No response READY");
                return false;
            }
        }
        imp.sleep(0.01);
    }

    return true;
}

//////////////////////////////////
// General Functions
function hex_to_i(hex) {
    local result = 0;
    local shift = hex.len() * 4;

    // For each digit..
    for(local d = 0; d < hex.len(); d++) {
        local digit;

        // Convert from ASCII Hex to integer
        if(hex[d] >= 0x61)
            digit = hex[d] - 0x57;
        else if(hex[d] >= 0x41)
             digit = hex[d] - 0x37;
        else
             digit = hex[d] - 0x30;

        // Accumulate digit
        shift -= 4;
        result += digit << shift;
    }

    return result;
}

function flash_leds_for_tag() {
    hardware.pin8.write(0.5);
    hardware.pin9.write(0.5);
    imp.sleep(0.7);
    hardware.pin8.write(0);
    hardware.pin9.write(0);
}

function flash_error() {
    hardware.pin8.write(0.01);
}

function log(string) {
  if (DEBUG) {
    server.log(string);
    agent.send("sendlog", string);
  }
}

function error(string) {
    flash_error();
    log(string);
}

function run_loop() {
    if (nfc_booted) {
        // Run this loop again, soon
        imp.wakeup(RUNLOOP_INTERVAL, run_loop);

        // Scan for nearby NFC devices

        nfc_scan();

        // Enter target mode.  This allows other readers to read our id.
        nfc_p2p_target();
    } else {
        error("PN532 could not be initialized, halting.");
    }
}

agent.on("debug", function(newState) {
  DEBUG = newState;
  log(format("Debug changed to %s", newState.tostring()));
});

// Configure LEDs
hardware.pin8.configure(PWM_OUT, 0.05, 0);
hardware.pin9.configure(PWM_OUT, 0.05, 0);

// Start up SPI
spi_init();

// Looks like this was a cold boot.
//imp.configure("FS13 Badge", [], []);
imp.setpowersave(!DEBUG);

// Parse out our hardware id from the impee id chip
device_id <- hardware.getimpeeid().slice(0, 6);
device_id_a <- hex_to_i(device_id.slice(0,2));
device_id_b <- hex_to_i(device_id.slice(2,4));
device_id_c <- hex_to_i(device_id.slice(4,6));

log("Booting, my ID is " + device_id);

// Start up the NXP chip and enter the main runloop
nfc_init();
run_loop();
function watchdog() {imp.wakeup(60, watchdog);}watchdog();
