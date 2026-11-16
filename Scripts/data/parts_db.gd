## Каталог деталей для «Листа деталей».
## SIM — соответствие детали компоненту симуляции (пусто = пока декоративная).

const PARTS := [
	{"id": "psu5v", "name": "Блок питания 5 В", "category": "Прочее"},
	{"id": "r220", "name": "Резистор 220 Ом", "category": "Резисторы"},
	{"id": "r1k", "name": "Резистор 1 кОм", "category": "Резисторы"},
	{"id": "r10k", "name": "Резистор 10 кОм", "category": "Резисторы"},
	{"id": "r100k", "name": "Резистор 100 кОм", "category": "Резисторы"},
	{"id": "r1m", "name": "Резистор 1 МОм", "category": "Резисторы"},
	{"id": "c100n", "name": "Конденсатор 100 нФ", "category": "Конденсаторы"},
	{"id": "c10u", "name": "Конденсатор 10 мкФ", "category": "Конденсаторы"},
	{"id": "c470u", "name": "Конденсатор 470 мкФ", "category": "Конденсаторы"},
	{"id": "led_red", "name": "Светодиод красный 5 мм", "category": "Светодиоды"},
	{"id": "led_green", "name": "Светодиод зелёный 5 мм", "category": "Светодиоды"},
	{"id": "led_ir", "name": "Светодиод ИК", "category": "Светодиоды"},
	{"id": "q_bc547", "name": "Транзистор BC547", "category": "Транзисторы"},
	{"id": "q_2n2222", "name": "Транзистор 2N2222", "category": "Транзисторы"},
	{"id": "q_irf540", "name": "MOSFET IRF540", "category": "Транзисторы"},
	{"id": "ic_ne555", "name": "Таймер NE555", "category": "Микросхемы"},
	{"id": "ic_7805", "name": "Стабилизатор LM7805", "category": "Микросхемы"},
	{"id": "ic_atmega", "name": "ATmega328P (Arduino Uno)", "category": "Микросхемы"},
	{"id": "ic_esp32", "name": "ESP32-WROOM", "category": "Микросхемы"},
	{"id": "ic_l293d", "name": "Драйвер моторов L293D", "category": "Микросхемы"},
	{"id": "s_dht11", "name": "Датчик DHT11", "category": "Датчики"},
	{"id": "s_ds18b20", "name": "Датчик DS18B20", "category": "Датчики"},
	{"id": "s_ldr", "name": "Фоторезистор", "category": "Датчики"},
	{"id": "s_hcsr04", "name": "Дальномер HC-SR04", "category": "Датчики"},
	{"id": "bread830", "name": "Макетка 830 точек", "category": "Прочее"},
	{"id": "w_mm", "name": "Перемычки папа-папа", "category": "Прочее"},
	{"id": "lcd1602", "name": "Дисплей LCD 1602", "category": "Прочее"},
	{"id": "pot10k", "name": "Потенциометр 10 кОм", "category": "Прочее"},
	{"id": "btn", "name": "Кнопка тактовая", "category": "Прочее"},
	{"id": "buzzer", "name": "Зуммер 5 В", "category": "Прочее"},
	{"id": "servo", "name": "Сервопривод SG90", "category": "Прочее"},
]

const SIM := {
	"psu5v": {"type": "vsource", "value": 5.0},
	# ATmega328P (Arduino Uno): пин L = цифровой пин 13 (программируемый источник),
	# пин R = GND; напряжение меняет код из редактора (HIGH=5 В, LOW=0 В)
	"ic_atmega": {"type": "vsource", "value": 0.0},
	"r220": {"type": "resistor", "value": 220.0},
	"r1k": {"type": "resistor", "value": 1000.0},
	"r10k": {"type": "resistor", "value": 10000.0},
	"r100k": {"type": "resistor", "value": 100000.0},
	"r1m": {"type": "resistor", "value": 1000000.0},
	"led_red": {"type": "led", "value": 2.0, "color": Color(0.9, 0.15, 0.12)},
	"led_green": {"type": "led", "value": 2.2, "color": Color(0.25, 0.9, 0.3)},
	"led_ir": {"type": "led", "value": 1.2, "color": Color(0.45, 0.12, 0.1)},
}

static func sim_of(id: String) -> Dictionary:
	return SIM.get(id, {})

static func get_part(id: String) -> Dictionary:
	for p in PARTS:
		if p["id"] == id:
			return p
	return {}
