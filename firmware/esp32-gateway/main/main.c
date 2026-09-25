#include <stdio.h>
#include "esp_log.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "ESP32_GATEWAY";

void app_main(void)
{
    ESP_LOGI(TAG, "===============================================");
    ESP_LOGI(TAG, "BLE Mesh Attendance — Classroom Gateway Boot");
    ESP_LOGI(TAG, "Target: ESP32-S3");
    ESP_LOGI(TAG, "Status: Repository Initialized / Minimal Boot");
    ESP_LOGI(TAG, "===============================================");

    while (1) {
        ESP_LOGI(TAG, "Gateway standby — awaiting Phase 1 BLE advertisement implementation");
        vTaskDelay(pdMS_TO_TICKS(10000));
    }
}
