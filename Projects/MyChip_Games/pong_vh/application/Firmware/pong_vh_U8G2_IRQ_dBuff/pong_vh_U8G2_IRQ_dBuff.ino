/*

  pong_vh_U8G2_IRQ_dBuff.ino
  for SH1106(1.3")
  Using Universal 8bit Graphics Library (https://github.com/olikraus/u8g2/)

  MyChip-on-MyDesk
  https://groups.google.com/g/mychip-on-mydesk
*/

#include <Arduino.h>
#include <U8g2lib.h>
#include <Wire.h> // Hardware I2C

#ifdef PWM_PI_PICO
U8G2_SSD1306_128X64_NONAME_F_HW_I2C u8g2(U8G2_R0, /* reset=*/ U8X8_PIN_NONE);
#else
U8G2_SH1106_128X64_NONAME_1_HW_I2C u8g2(U8G2_R0, /* reset=*/ U8X8_PIN_NONE);
#endif

#define SCREEN_WIDTH  128
#define SCREEN_HEIGHT 64
#define SCREEN_W_BYTE (SCREEN_WIDTH/8)  // 16
unsigned char *TableBMP;
unsigned char TableBMP_Even[SCREEN_W_BYTE*SCREEN_HEIGHT];
unsigned char TableBMP_Odd[SCREEN_W_BYTE*SCREEN_HEIGHT];
bool  bEven = true;

#include "MyGames_pin_mapping.h"

#define DRAW_BITMAP() { \
    u8g2.firstPage();  \
    do { \
      u8g2.drawBitmap(0, 0, SCREEN_W_BYTE, SCREEN_HEIGHT, bEven? TableBMP_Odd:TableBMP_Even); \
    } while( u8g2.nextPage() ); \
  }

// PWM for Clock generator -----------------------
#define _PWM_LOGLEVEL_    3
#include "RP2040_PWM.h"
RP2040_PWM* PWM_Instance; //creates pwm instance
float frequency = 600000; //  Freq
float dutyCycle = 50;     //  Duty in %
//------------------------------------------------

void u8g2_prepare(void)
{
    u8g2.setFont(u8g2_font_6x10_tf);
    u8g2.setFontRefHeightExtendedText();
    u8g2.setDrawColor(1);
    u8g2.setFontPosTop();
    u8g2.setFontDirection(0);
}

//---------------------------------------------------------------
int cnt_p_tick = 0;
int nFrame = 0;

void setup(void)
{
  // Pin Mode setup --------------------------------------
  // 5-Way Switch Input (Pull-Up)
  pinMode(PIN_SW_F, INPUT);
  pinMode(PIN_SW_B, INPUT);
  pinMode(PIN_SW_L, INPUT);
  pinMode(PIN_SW_R, INPUT);
  pinMode(PIN_SW_M, INPUT);
  // IO with FPGA or MyChip
  pinMode(PIN_RESET, OUTPUT);
  pinMode(PIN_V_SYNC, INPUT);
  pinMode(PIN_PIXEL, INPUT);
  pinMode(PIN_P_TICK, INPUT);
  pinMode(PIN_BTN_LEFT, OUTPUT);
  pinMode(PIN_BTN_RIGHT, OUTPUT);
  pinMode(PIN_BTN_UP, OUTPUT);
  pinMode(PIN_BTN_DOWN, OUTPUT);
  pinMode(PIN_GAME_NEW, OUTPUT);
  pinMode(PIN_GAME_OVER, INPUT);
  pinMode(PIN_GAME_COMPLETE, INPUT);

  // Initial value -----------------------------------------
  digitalWrite(PIN_RESET, HIGH);      // Reset, active HIGH
  digitalWrite(PIN_BTN_LEFT, HIGH);   // Move Left, active LOW
  digitalWrite(PIN_BTN_RIGHT, HIGH);  // Move Right, active LOW
  digitalWrite(PIN_BTN_UP, HIGH);     // Move Up, active LOW
  digitalWrite(PIN_BTN_DOWN, HIGH);   // Move Down, active LOW
  digitalWrite(PIN_GAME_NEW, HIGH);   // New Game, active LOW

  // OLED Driver -------------------------------------------
  u8g2.begin();

  // Splash ------------------------------------------------
//  for (int i=0; i<SCREEN_W_BYTE*SCREEN_HEIGHT; i++)
//    TableBMP_Odd[i] = 0xAA;
//  bEven = true;
//  DRAW_BITMAP();

//  for (int i=0; i<SCREEN_W_BYTE*SCREEN_HEIGHT; i++)
//    TableBMP_Even[i] = 0x55;
//  bEven = false;
//  DRAW_BITMAP();

  bEven = true;
  TableBMP = TableBMP_Even;

  u8g2.firstPage();  
  do {
    u8g2_prepare();
    u8g2.drawStr(0, 0, "MyChip-on-MyDesk");
    u8g2.drawStr(0,12, "MyGame-on-MyChip");
    u8g2.drawStr(0,24, "Pong VH");
    u8g2.drawStr(0,36, ">> Press Start Button");
  } while( u8g2.nextPage() );
  
  // PWM for Clock generator----------------------------
  PWM_Instance = new RP2040_PWM(PIN_CLK, frequency, dutyCycle);

  // Attach the interrupt to the pin
  attachInterrupt(digitalPinToInterrupt(PIN_P_TICK),    handlerP_TICK,    RISING);
  attachInterrupt(digitalPinToInterrupt(PIN_GAME_OVER), handlerGame_Over, RISING);
  attachInterrupt(digitalPinToInterrupt(PIN_V_SYNC),    handlerV_SYNC,    RISING);

  digitalWrite(PIN_RESET, LOW); // Release Reset
}

//-------------------------------------------------------------------
// Multi-Core:
bool bUpdateBuffer = false;
void setup1(void)
{
}

void loop1()
{
  if (bUpdateBuffer)
  {
    DRAW_BITMAP();
    bUpdateBuffer = false;
    nFrame++;
  }
}

#define DEBOUNCE_DELAY 20

void loop(void)
{
  PWM_Instance->setPWM(PIN_CLK, frequency, dutyCycle);

  while(true)
  {
    if (!digitalRead(PIN_SW_F))
    {
      delay(DEBOUNCE_DELAY);  // Delay 20ms
      digitalWrite(PIN_BTN_LEFT, LOW);
    }
    else
    {
      delay(DEBOUNCE_DELAY);  // Delay 20ms
      digitalWrite(PIN_BTN_LEFT, HIGH);
    }

    if (!digitalRead(PIN_SW_B))
    {
      delay(DEBOUNCE_DELAY);  // Delay 20ms
      digitalWrite(PIN_BTN_RIGHT, LOW);
    }
    else
    {
      delay(DEBOUNCE_DELAY);  // Delay 20ms
      digitalWrite(PIN_BTN_RIGHT, HIGH);
    }

    if (!digitalRead(PIN_SW_R))
    {
      delay(DEBOUNCE_DELAY);  // Delay 20ms
      digitalWrite(PIN_BTN_UP, LOW);
    }
    else
    {
      delay(DEBOUNCE_DELAY);  // Delay 20ms
      digitalWrite(PIN_BTN_UP, HIGH);
    }

    if (!digitalRead(PIN_SW_L))
    {
      delay(DEBOUNCE_DELAY);  // Delay 20ms
      digitalWrite(PIN_BTN_DOWN, LOW);
    }
    else
    {
      delay(DEBOUNCE_DELAY);  // Delay 20ms
      digitalWrite(PIN_BTN_DOWN, HIGH);
    }

    if (!digitalRead(PIN_SW_M))
    {
      delay(DEBOUNCE_DELAY);  // Delay 20ms
      digitalWrite(PIN_GAME_NEW, LOW);
//      if (digitalRead(PIN_GAME_COMPLETE))
//        digitalWrite(PIN_RESET, HIGH);
    }
    else
    {
      delay(DEBOUNCE_DELAY);  // Delay 20ms
      digitalWrite(PIN_GAME_NEW, HIGH);
//      digitalWrite(PIN_RESET, LOW);
    }
  }
}

// Interrupt Handlers -----------------------------------------------------
void handlerP_TICK()
{
  int xPos = cnt_p_tick%SCREEN_WIDTH;
  int yPos = cnt_p_tick/SCREEN_WIDTH;
  int address = (yPos*SCREEN_W_BYTE)+xPos/8;

  if(!(xPos%8))  TableBMP[address] = 0x00;

  if (digitalRead(PIN_PIXEL))
    TableBMP[address] |= (uint8_t)(0x80>>(xPos%8));
  else
    TableBMP[address] &= ~(0x80>>(xPos%8));

  cnt_p_tick++;
}

void handlerGame_Over()
{
  char szBuffer[32];

  u8g2.begin();
  u8g2.firstPage();
  do {
    u8g2.drawStr(15,12, "Game Over");
    sprintf(szBuffer,"Your Score is %d", nFrame);
    u8g2.drawStr(15,24, szBuffer);
    u8g2.drawStr(0,36, ">> Press Start Button");
  } while( u8g2.nextPage());

  bEven = true;
  bUpdateBuffer = false;
  nFrame = 0;
  cnt_p_tick = 0;
}

void handlerV_SYNC()
{
  if (bEven)
  {
    bEven = false;
    TableBMP = TableBMP_Odd;
  }
  else
  {
    bEven = true;
    TableBMP = TableBMP_Even;
  }
  bUpdateBuffer = true;
  cnt_p_tick = 0;
}

