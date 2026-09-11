#include "cJSON.h"
#include "driver/spi_common.h"
#include "esp_err.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "font.h"
#include "freertos/FreeRTOS.h"
#include "freertos/projdefs.h"
#include "freertos/task.h"
#include "hal/spi_types.h"
#include "lwip/err.h"
#include "nvs_flash.h"
#include <driver/gpio.h>
#include <driver/spi_master.h>
#include <esp_http_client.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>

#define OLED_DC 9
#define OLED_RES 8
#define ROWS_MAX 7
#define COLS_MAX 21
#define WIFI_SSID CONFIG_NETZF_WIFI_SSID
#define WIFI_PASSWORD CONFIG_NETZF_WIFI_PASSWORD
#define VIEWPORT "meta"
#define NETZF_SERVER "http://192.168.29.203:8989"
#define EMPTY_ROW "                     "

static bool wifi_connected = false;

// Fixed-size working buffers — static so they live in .bss, not on the task
// stack
static uint8_t framebuffer[1024];
static char json_buf[4096];

void oled_command(spi_device_handle_t spi, uint8_t cmd) {
  gpio_set_level(OLED_DC, 0); // Sending command
  spi_transaction_t t = {
      .length = 8,
      .tx_buffer = &cmd,
  };
  spi_device_transmit(spi, &t);
}

void oled_data(spi_device_handle_t spi, const uint8_t *data, size_t len) {
  gpio_set_level(OLED_DC, 1); // DC=1: these bytes are pixel data
  spi_transaction_t t = {
      .length = len * 8, // len bytes = len*8 bits
      .tx_buffer = data,
  };
  spi_device_transmit(spi, &t);
}

void oled_init(spi_device_handle_t spi) {
  // --- display config ---
  oled_command(spi, 0xAE); // display OFF (start off, turn on at the end)
  oled_command(spi, 0xD5); // set clock divide ratio
  oled_command(spi, 0x80); //   ratio value
  oled_command(spi, 0xA8); // set multiplex ratio
  oled_command(spi, 0x3F); //   64 rows (1/64 duty)
  oled_command(spi, 0xD3); // set display offset
  oled_command(spi, 0x00); //   no offset
  oled_command(spi, 0x40); // set start line

  // --- charge pump (generates the high voltage the pixels need) ---
  oled_command(spi, 0x8D); // charge pump setting
  oled_command(spi, 0x14); //   ENABLE it (without this, nothing lights up)

  // --- memory addressing ---
  oled_command(spi, 0x20); // set memory mode
  oled_command(spi, 0x00); //   horizontal addressing

  // --- orientation ---
  oled_command(spi, 0xA1); // segment remap
  oled_command(spi, 0xC8); // COM scan direction
  oled_command(spi, 0xDA); // COM pins config
  oled_command(spi, 0x12); //   alternative config

  // --- brightness ---
  oled_command(spi, 0x81); // contrast control
  oled_command(spi, 0xCF); //   contrast value
  oled_command(spi, 0xD9); // pre-charge period
  oled_command(spi, 0xF1); //   pre-charge value
  oled_command(spi, 0xDB); // VCOMH deselect level
  oled_command(spi, 0x40); //   VCOMH value

  // --- display mode ---
  oled_command(spi, 0xA4); // resume from RAM (not "all pixels on")
  oled_command(spi, 0xA6); // normal (not inverted)

  // --- the big one ---
  oled_command(spi, 0xAF); // display ON
}

void write_char(uint8_t row, uint8_t col, uint8_t c, uint8_t fb[1024]) {
  int x = col * 6; // Pixel Coordinates
  int y = row * 8; // Pixel Coordinates

  // Fetch the font glyph
  uint8_t page = y / 8;
  for (int i = 0; i < 5; i++) {
    fb[page * 128 + (x + i)] = font[(c * 5) + i];
  }
}

void write_grid(uint8_t grid[ROWS_MAX - 2][COLS_MAX + 1], uint8_t fb[1024]) {
  // First Two Rows is the Bar (row 0 = status, row 1 = reserved blank)
  uint8_t status[COLS_MAX];
  uint8_t wifi_status[3] = "--";
  if (wifi_connected) {
    wifi_status[0] = 'O';
    wifi_status[1] = 'K';
  }
  sprintf((char *)status, "NetzFenster! WiFi %s", wifi_status);
  for (int i = 0; i < COLS_MAX; i++) {
    write_char(0, i, status[i], fb);
  }

  // Now the other rows
  for (int r = 0; r < ROWS_MAX - 2; r++) {
    for (int c = 0; c < COLS_MAX; c++) {
      write_char(r + 2, c, grid[r][c], fb);
    }
  }
}

static void wifi_event_handler(void *arg, esp_event_base_t base, int32_t id,
                               void *data) {
  if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
    esp_wifi_connect();
  } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
    printf("wifi: disconnected, retrying...\n");
    esp_wifi_connect();
  } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
    ip_event_got_ip_t *event = (ip_event_got_ip_t *)data;
    printf("wifi: got IP " IPSTR "\n", IP2STR(&event->ip_info.ip));
    wifi_connected = true;
  }
}

static void wifi_init_sta(void) {
  ESP_ERROR_CHECK(nvs_flash_init());
  ESP_ERROR_CHECK(esp_netif_init());
  ESP_ERROR_CHECK(esp_event_loop_create_default());
  esp_netif_create_default_wifi_sta();

  wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
  ESP_ERROR_CHECK(esp_wifi_init(&cfg));

  ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID,
                                             &wifi_event_handler, NULL));
  ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP,
                                             &wifi_event_handler, NULL));

  wifi_config_t wifi_config = {
      .sta =
          {
              .ssid = WIFI_SSID,
              .password = WIFI_PASSWORD,
              .threshold.authmode = WIFI_AUTH_WPA2_PSK,
          },
  };
  ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
  ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_config));
  ESP_ERROR_CHECK(esp_wifi_start());
}

typedef struct {
  char *buf;
  size_t len;
  size_t cap;
} http_ctx_t;

esp_err_t http_event_handler(esp_http_client_event_t *e) {
  http_ctx_t *ctx = e->user_data;
  if (e->event_id == HTTP_EVENT_ON_DATA) {
    if (ctx->len + e->data_len < ctx->cap) {
      memcpy(ctx->buf + ctx->len, e->data, e->data_len);
      ctx->len += e->data_len;
      ctx->buf[ctx->len] = '\0';
    }
  }
  return ESP_OK;
}

static esp_err_t fetch_frame_data(const char *url, char *buf, size_t cap) {
  http_ctx_t ctx = {.buf = buf, .len = 0, .cap = cap};

  esp_http_client_config_t config = {.url = url,
                                     .user_data = &ctx,
                                     .method = HTTP_METHOD_GET,
                                     .event_handler = http_event_handler};
  esp_http_client_handle_t client = esp_http_client_init(&config);
  if (client == NULL) {
    return ESP_FAIL;
  }
  esp_err_t err = esp_http_client_perform(client);
  esp_http_client_cleanup(client);
  return err;
};

void app_main(void) {
  wifi_init_sta();

  spi_bus_config_t bus_config = {
      .mosi_io_num = 11,
      .miso_io_num = -1,
      .sclk_io_num = 12,
      .max_transfer_sz = 4096,
      .quadhd_io_num = -1,
      .quadwp_io_num = -1,
  };
  spi_device_interface_config_t dev_conf = {
      .clock_speed_hz = 1 * 1000 * 1000,
      .mode = 0,
      .spics_io_num = -1,
      .queue_size = 1,
  };

  spi_device_handle_t spi;
  spi_bus_initialize(SPI2_HOST, &bus_config, SPI_DMA_CH_AUTO);
  spi_bus_add_device(SPI2_HOST, &dev_conf, &spi);

  gpio_set_direction(OLED_DC, GPIO_MODE_OUTPUT);
  gpio_set_direction(OLED_RES, GPIO_MODE_OUTPUT);
  gpio_set_level(OLED_RES, 0);   // reset LOW (hold in reset)
  vTaskDelay(pdMS_TO_TICKS(10)); // wait 10ms
  gpio_set_level(OLED_RES, 1);   // reset HIGH (let it run)

  oled_init(spi);
  // Screen Ready!
  char url[128];
  snprintf(url, sizeof(url), "%s/frame?viewport=%s&rows=%d&cols=%d",
           NETZF_SERVER, VIEWPORT, ROWS_MAX - 2, COLS_MAX);

  memset(framebuffer, 0,
         1024); // redundant now (static starts zeroed) — kept for clarity

  // Hardcoded 21x8 grid (v0) — this is what the server will send in v1
  uint8_t grid[ROWS_MAX - 2][COLS_MAX + 1] = {"    Connecting..     ",
                                              EMPTY_ROW,
                                              EMPTY_ROW,
                                              EMPTY_ROW,
                                              EMPTY_ROW};

  while (!wifi_connected) {
    write_grid(grid, framebuffer);
    oled_data(spi, framebuffer, sizeof(framebuffer));
    vTaskDelay(pdMS_TO_TICKS(1000)); // wait 1 second
  }
  // Wifi Connected Now!
  //
  strcpy((char *)grid[0], "    Fetching....     ");

  // Paste the Network Framebuffer
  while (true) {
    double refresh_delay = 30000; // 30 seconds by default
    esp_err_t err = fetch_frame_data(url, json_buf, sizeof(json_buf));
    if (err != ESP_OK) {
      printf("Fetching Failed!: %s", json_buf);
      vTaskDelay(pdMS_TO_TICKS(refresh_delay)); // Wait 30 seconds
      continue;
    }
    cJSON *root = cJSON_Parse(json_buf);
    cJSON *frames = cJSON_GetObjectItem(root, "frames");
    int len_frames = cJSON_GetArraySize(frames);
    for (int i = 0; i < len_frames; i++) {
      cJSON *frame = cJSON_GetArrayItem(frames, i);
      cJSON *rows = cJSON_GetObjectItem(frame, "rows");
      for (int j = 0; j < ROWS_MAX - 2; j++) {
        int8_t row_data[COLS_MAX + 1] = EMPTY_ROW;
        cJSON *row = cJSON_GetArrayItem(rows, j);
        if (row != NULL) {
          strncpy((char *)row_data, row->valuestring, COLS_MAX);
        }
        memcpy(grid[j], row_data, COLS_MAX + 1);
      }
      write_grid(grid, framebuffer);
      oled_data(spi, framebuffer, sizeof(framebuffer));
      // frame dwell
      cJSON *frame_dwell_ms_n = cJSON_GetObjectItem(root, "frame_dwell_ms");
      double frame_dwell_ms = 1000;
      if (frame_dwell_ms_n != NULL) {
        frame_dwell_ms = cJSON_GetNumberValue(frame_dwell_ms_n);
      }
      vTaskDelay(pdMS_TO_TICKS(frame_dwell_ms)); // Wait 10 seconds
    }
    cJSON *refresh_ms_n = cJSON_GetObjectItem(root, "refresh_ms");
    if (refresh_ms_n != NULL) {
      refresh_delay = cJSON_GetNumberValue(refresh_ms_n);
    }
    vTaskDelay(pdMS_TO_TICKS(refresh_delay));
  }
}
