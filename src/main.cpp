#include <Arduino.h>
#include <math.h>

static int conf_analog_pin = A0;
static const float conf_calibration = 247.0;

static float acc_voltage(int analog_pin, float calibration)
{
    static const int values = 1000;
    static float reference_voltage = 5.0;

    float voltage_sum = 0;
    float voltage_squared_sum = 0;
    for (int i = 0; i < values; i++)
    {
        const auto value = static_cast<float>(analogRead(analog_pin));
        voltage_sum += value;
        voltage_squared_sum += (value * value);
    }

    const float avg_voltage = (voltage_sum / values);
    const float variance = (voltage_squared_sum / values) - (avg_voltage * avg_voltage);
    const float rms = sqrt(variance);
    const float voltage = (rms * (reference_voltage / 1023.0)) * calibration;

    return voltage;
}

void setup()
{
    Serial.begin(115200);
}

void loop()
{
    Serial.println(acc_voltage(conf_analog_pin, conf_calibration));
    delay(500);
}
