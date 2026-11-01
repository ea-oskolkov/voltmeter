#!/bin/bash

set -u

readonly CONF_BAUD_RATE=115200 # Скорость обмена данными по последовательному порту.
readonly CONF_MINIMUM_VOLTAGE=190 # Минимально допустимое напряжение до запуска таймера.
readonly CONF_SHUTDOWN_DELAY_SECONDS=600 # Сколько ожидать поднятия напряжения перед запуском обработчика.

# Печатает сообщение
log_message()
{
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# Возвращает текующую временную метку
now()
{
    date +%s
}

# Печатает справку
print_usage()
{
    printf "Usage: $0 <serial-port>\n" >&2
}

# Подготавливает и открывает последовательный порт для чтения/записи.
#
# Проверяет наличие порта, настраивает скорость и параметры терминала,
# после чего открывает его на файловом дескрипторе 3.
configure_serial_port()
{
    local serial_port=$1

    if [[ ! -c "$serial_port" ]] then
        log_message "Error: serial port is unavailable: $serial_port" >&2
        return 1
    fi

    if ! stty -F "$serial_port" "$CONF_BAUD_RATE" raw -echo -ixon 2>/dev/null ; then
        log_message "Error: cannot configure serial port: $serial_port" >&2
        return 1
    fi

    if ! exec 3<>"$serial_port" 2>/dev/null ; then
        log_message "Error: cannot open serial port: $serial_port" >&2
        return 1
    fi

    return 0
}

# Обработчик отсутствия напряжения на протяжении N секунд
no_voltage_handler()
{
    shutdown -h now
    exit 0
}

# Проверяет, что напряжение ниже минимального порога.
#
# Ожидается, что значение уже прошло валидацию в цикле.
#
# Возвращает:
#   0 - если voltage < MINIMUM_VOLTAGE
#   1 - если voltage >= MINIMUM_VOLTAGE
is_voltage_below_minimum()
{
    local voltage=$1

    awk -v voltage="$voltage" -v minimum="$CONF_MINIMUM_VOLTAGE" '
        BEGIN {
            exit !(voltage + 0 < minimum)
        }
    '
}

# Основной рабочий цикл
main_loop()
{
    local timer_start_timepoint=''
    local voltage=''
    local current_time=''

    while true; do
        voltage=''
        if ! IFS= read -r -t 1 voltage <&3 ; then
            sleep 0.5
            continue
        fi

        voltage=${voltage%$'\r'}
        voltage=${voltage//[[:space:]]/}
        if [[ ! "$voltage" =~ ^[0-9]+([.][0-9]+)?$ ]] then
            log_message "Warning: ignoring invalid voltage reading: [$voltage]"
            continue
        fi

        if is_voltage_below_minimum "$voltage" ; then
            if [[ -z "$timer_start_timepoint" ]] then
                timer_start_timepoint=$(now)
                log_message "Voltage is below $CONF_MINIMUM_VOLTAGE V; timer started."
            fi
        elif [[ -n "$timer_start_timepoint" ]] then
            timer_start_timepoint=''
            log_message "Voltage recovered above $CONF_MINIMUM_VOLTAGE V; timer cancelled."
            continue
        fi

        if [[ -n "$timer_start_timepoint" ]] then
            current_time=$(now)
            if (( current_time - timer_start_timepoint >= CONF_SHUTDOWN_DELAY_SECONDS ))
            then
                no_voltage_handler
            fi
        fi
    done
}

############ MAIN ############
if [[ $# -ne 1 ]] then
    print_usage
    exit 2
fi

readonly SERIAL_PORT=$1
if ! configure_serial_port "$SERIAL_PORT" ; then
    exit 1
fi

log_message \
    "Monitoring $SERIAL_PORT at $CONF_BAUD_RATE baud; threshold: $CONF_MINIMUM_VOLTAGE V for " \
    "$CONF_SHUTDOWN_DELAY_SECONDS seconds."

main_loop

##############################
