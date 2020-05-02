; Input Capture Register on Timer 1 Demo
; Timing Ultrasonic Ping Sensor pulse width and calculating 
; based on speed of sound at 337 Meters/Second.  
; Speed of sound Seconds per Meter = 1/( 337 Meters / Second) = 2.967 mS/Meter
; Speed of sound at 3000 ft elevation is approximately 337 Meters/Second

.nolist
.include "m328pdef.inc"
.list

.equ	pwMin = 600  ; 600 microSecond Pulse Width
.equ	pwMax = 2300  ; 2300 microSecond Pulse Width
.equ	pwMid = (pwMax - pwMin) / 2
.equ	pingMax = 6000 ; 6000 uS round trip time for 1 meter
.equ	pingMin = 183 ; 183 uS round trip for 3 cM
.equ	pulseMap = 19153 ;
;  PWMbH..L = ((InCapH..L - pingMinH..L) * pulseMapH..L)[Byte3..2] + pwMinH..L 

.def	TEMPH = R17
.def	TEMP = R16
.def 	InCapH = R7
.def	InCapL = R6
.def	PWMbH = R15
.def	PWMbL = R14
.def	PWMaxH = R13
.def	PWMaxL = R12
.def	PWMidH = R11
.def	PWMidL = R10
.def	PWMinH = R9
.def	PWMinL = R8


;--------------------Registers Used for multiply Funcdtion----------- 
.def	m1H = R19
.def	m1L = R18
.def	m2H = R21
.def	m2L = R20
.def	res3 = R25	; MSB of 32 bit result (4 bytes)
.def	res2 = R24
.def	res1 = R23
.def	res0 = R22	; LSB of 32 bit result
.def	ZERO = R4
//-------------------------------------------------------------------

.ORG	$0000
		rjmp	RESET
.ORG	ICP1addr
		rjmp	captureISR
.ORG	OVF1addr
		rjmp	OVF1isr
.ORG	INT_VECTORS_SIZE
RESET:
		ldi 	TEMP, high(RAMEND)
		out 	SPH, TEMP
		ldi 	TEMP, low(RAMEND)
		out 	SPL, TEMP

		ldi 	TEMP, high(PWMax)
		mov 	PWMaxH, TEMP
		ldi 	TEMP, low(PWMax)
		mov 	PWMaxL, TEMP

		ldi 	TEMP, high(PWMid)
		mov 	PWMidH, TEMP
		ldi 	TEMP, low(PWMid)
		mov 	PWMidL, TEMP

		ldi 	TEMP, high(PWMin)
		mov 	PWMinH, TEMP
		ldi 	TEMP, low(PWMin)
		mov 	PWMinL, TEMP



		sbi 	DDRB, PB2 ; OC1B PWM output pin
		cbi 	DDRB, PB0 ; Input Capture Input
		sbi 	PORTB, PB0 ; Pullup Enabled
		sbi 	DDRB, PB1	; Output pin to Ping Sensor Trigger

		ldi 	TEMP, high(20000)
		sts 	OCR1AH, TEMP
		ldi 	TEMP, low(20000)
		sts 	OCR1AL, TEMP	; PWM Top Register

		ldi 	TEMP, high(1500)
		mov 	PWMbH, TEMP
		sts 	OCR1BH, PWMbH	;PWM Servo Mid Position High Byte

		ldi 	TEMP, low(1500)
		mov 	PWMbL, TEMP
		sts 	OCR1BL, PWMbL	;PWM Servo Mid Position Low Byte

		ldi 	TEMP, (1<<ICIE1)|(1<<TOIE1)
		sts 	TIMSK1, TEMP	;Input Capture Interrupt Enable

		ldi 	TEMP, (1<<COM1B1)|(0<<COM1B0)|(1<<WGM11)|(1<<WGM10)
		sts 	TCCR1A, TEMP

		ldi 	TEMP, (1<<ICES1)|(1<<WGM13)|(1<<WGM12)|(0<<CS02)|(0<<CS01)|(1<<CS00)
		sts 	TCCR1B, TEMP

		sei

//-------------------------------------------------------------------
MAIN:
		nop
		nop
		rjmp	MAIN

//-------------------------------------------------------------------
captureISR:
		push	TEMP
		push	TEMPH
		lds 	TEMP, TCCR1B
		sbrc 	TEMP, ICES1
		rjmp	StartCapture
;End Capture
		sbr 	TEMP, (1<<ICES1)
		sts 	TCCR1B, TEMP
		lds  	TEMP, ICR1L
		lds 	TEMPH, ICR1H
		sub 	TEMP, InCapL
		mov 	InCapL, TEMP
		sbc 	TEMPH, InCapH
		mov 	InCapH, TEMPH
		rcall	checkPing
		mov 	M1H, InCapH
		mov 	M1L, InCapL
		subi 	M1L, low(pingMin)
		sbci	M1H, high(pingMin)
		rcall	mul16
		ldi 	TEMP, low(pwMin)
		add 	res2, TEMP
		ldi 	TEMP, high(pwMin)
		adc 	res3, TEMP
		mov 	PWMbH, res3
		mov 	PWMbL, res2
//		sts 	OCR1BH, PWMbH
//		sts 	OCR1BL, PWMbL
		pop 	TEMPH
		pop 	TEMP
		reti
StartCapture:
		cbr 	TEMP, (1<<ICES1)
		sts 	TCCR1B, TEMP
		lds  	InCapL, ICR1L
		lds 	InCapH, ICR1H
		pop 	TEMPH
		pop 	TEMP
		reti

//-------------------------------------------------------------------
OVF1isr:
// Set input capture sense to rising edge and output short pulse to
//	 start Ping Sensor.  Timing pulse starts on rising edge on PB0.
		push	TEMP
		push	TEMPH
		lds 	TEMP, TCCR1B
		sbr 	TEMP, (1<<ICES1) ;Input Capture Rising Edge
		sts 	TCCR1B, TEMP
;Trigger Ping Sensor 10uS Pulse
		ldi 	TEMP, 5
		sbi 	PORTB, PB1
TriggerPing:
		dec 	TEMP
		brne	TriggerPing
		cbi 	PORTB, PB1
		pop 	TEMPH
		pop 	TEMP
		reti

//-------------------------------------------------------------------
checkPing:
// Verify ping pulse is valid in range for 3 cM to 1 Meter
// Ping range  Minimum: 183 uS ($B7)  Maximum: 6000 ($1770)
		push	TEMP
		ldi 	TEMP, low(pingMin)
		cp  	InCapL, TEMP
		ldi 	TEMP, high(pingMin)
		cpc 	InCapH, TEMP
		brpl	checkOver
		ldi 	TEMP, high(pingMin)
		mov 	inCapH, TEMP
		ldi 	TEMP, low(pingMin)
		mov 	inCapL, TEMP
		pop 	TEMP
		ret

checkOver:
		ldi 	TEMP, low(pingMax)
		cp  	InCapL, TEMP
		ldi 	TEMP, high(pingMax)
		cpc 	InCapH, TEMP
		brmi	return
		ldi 	TEMP, high(pingMax)
		mov 	inCapH, TEMP
		ldi 	TEMP, low(pingMax)
		mov 	inCapL, TEMP
return:
		pop 	TEMP
		ret

//-------------------------------------------------------------------

mul16:
		ldi 	M2H, high(pulseMap)
		ldi 	M2L, low(pulseMap)
		clr 	res3
		clr 	res2
		mul 	M1L, M2L	; Result to R1..R0
		mov 	res0, R0
		mov 	res1, R1
		mul 	M1L, M2H
		add 	res1, R0
		adc 	res2, R1
		mul 	M1H, M2L
		add 	res1, R0
		adc 	res2, R1
		adc 	res3, ZERO
		mul 	M1H, M2H
		add 	res2, R0
		adc 	res3, R1
		ret
