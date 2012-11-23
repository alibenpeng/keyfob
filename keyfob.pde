/*

  Alis garage door and home automation keyfob
  standby current consumption: <1µA!

*/

#include <JeeLib.h>
#include <avr/interrupt.h>   
#include <avr/sleep.h>   
#include <avr/power.h>   
#include <avr/wdt.h>   
#include <avr/eeprom.h>   
#include <util/delay.h>

#include "config.h"

#define DEBOUNCE_DELAY 30
#define NODE_ID 3
#define NETGROUP 42

#define LED_PIN 8
#define EEPROM_ID_ADDRESS 0x60


struct {
	uint16_t switch_id;
	uint16_t key_id;
} payload;


volatile bool state1 = 1;
volatile bool state2 = 1;
volatile bool state3 = 1;
volatile bool state4 = 1;


// debounce delay and pin status check in ISR
ISR( PCINT2_vect ) { 
  digitalWrite(LED_PIN, HIGH);
  _delay_ms(DEBOUNCE_DELAY); // debounce delay
  digitalWrite(LED_PIN, LOW);

	state1 = (PIND & (1 << PIND4));
	state2 = (PIND & (1 << PIND3));
	state3 = (PIND & (1 << PIND0));
	state4 = (PIND & (1 << PIND1));
}

static void init_RF12_OOK_transmit (void) {
  rf12_control(0x8027); // disabel tx register; disabel RX fifo buffer; xtal cap 12pf,
  rf12_control(0x8209); // enable xtal, disable clk pin
  rf12_control(0xa67C); // A67C    868.3000 MHz: 
  rf12_control(0xC606); // c606 57.6Kbps (38.4: 8, 19.2: 11, 9.6: 23, 4.8: 47)
  rf12_control(0x94A0); // VDI,FAST,134kHz,0dBm,-103dBm
  rf12_control(0xC2AC); //
  rf12_control(0xCA83); // FIFO8,SYNC,!ff,DR
  rf12_control(0xCE00); // SYNC=2
  rf12_control(0xC483); // @PWR,NO RSTRIC,!st,!fi,OE,EN
  rf12_control(0x9850); // !mp,90kHz Devation Frequenzabstand des High- und
  rf12_control(0xCC77); //
  rf12_control(0xE000); // NOT USE
  rf12_control(0xC800); // NOT USE
  rf12_control(0xC040); // 1.66MHz,2.2V
}

void garageSend() {
	int key1[98] = GARAGE_KEY;

  init_RF12_OOK_transmit();

	for (int j = 0; j < 3; j++) {
		for (int i = 0; i < 98; i++) {
			int value = key1[i];
			if (value == 1) {
					rf12_onOff(1);
					_delay_us(1007 + 150);
			} else {
					rf12_onOff(0);
					_delay_us(1007 - 200);
			}
  }
		rf12_onOff(0);
		_delay_us(8000);
	}

  wdt_enable(WDTO_15MS);
  while(1) {};
}



void cryptSend(int button) {
	rf12_recvDone();
	if (rf12_canSend()) {
		payload.key_id = button;
		rf12_sendStart(0, &payload, sizeof(payload));
		rf12_sendWait(1);
	}
}


void processButton() {
    if (state1 == 0) {
      cryptSend(0x01);
      garageSend();
    } 

    if (state2 == 0) {
      cryptSend(0x02);
    } 

    if (state3 == 0) {
      cryptSend(0x03);
    } 

    if (state4 == 0) {
      cryptSend(0x04);
    } 
}

void setup() {
  MCUSR = 0; // this is oh so important! It sets the MCU status register to 0, so the MCU doesn't keep rebooting itself!
  wdt_disable();

  // blink the LED
  digitalWrite(LED_PIN, HIGH);
  _delay_ms(DEBOUNCE_DELAY); // debounce delay
  digitalWrite(LED_PIN, LOW);

  // initialize RFM12
	rf12_initialize(NODE_ID, RF12_868MHZ, NETGROUP);
	rf12_encrypt(RF12_EEPROM_EKEY);
  payload.switch_id = eeprom_read_word((uint16_t*)EEPROM_ID_ADDRESS);

  // set pins 0,1,3,4 to input mode
	pinMode(PIND0, INPUT);
	pinMode(PIND1, INPUT);
	pinMode(PIND3, INPUT);
	pinMode(PIND4, INPUT);

  // enable internal pullups
	digitalWrite(PIND0, HIGH);
	digitalWrite(PIND1, HIGH);
	digitalWrite(PIND3, HIGH);
	digitalWrite(PIND4, HIGH);

  // make digital pins 0-1 and 3-4 into pin change interrupts  
  PCMSK2 |= (1 << PCINT16);
  PCMSK2 |= (1 << PCINT17);  
  PCMSK2 |= (1 << PCINT19);  
  PCMSK2 |= (1 << PCINT20);  

  PCICR |= (1 << PCIE2);      // enable pin change interrupts
}

void loop(){
	rf12_sleep(RF12_SLEEP);     // switch off RFM12
	wdt_disable();              // disable watchdog before sleeping
	sei();                      // enable interrupts
	Sleepy::powerDown();        // go to sleep!

// ---------------------------------------------------------------------------
// the controller is woken up by the pin change interrupt and jumps to the ISR
// after which it continues here!
// ---------------------------------------------------------------------------

	sleep_disable();            // first thing after waking from sleep
	wdt_enable(WDTO_1S);        // enable watchdog
	rf12_sleep(RF12_WAKEUP);    // wakeup RFM12
	processButton();            // the button state was set in the ISR
	wdt_reset();                // reset the watchdog after we successfully delivered our payload
}

// vim: expandtab sw=2 ts=2
