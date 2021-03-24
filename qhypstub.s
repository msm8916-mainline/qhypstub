/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (C) 2021 Stephan Gerhold
 *
 * Based on the "ARM Architecture Reference Manual for Armv8-A"
 * and EL2/EL1 initialization sequences adapted from Linux and U-Boot.
 */
.cpu	cortex-a53

.equ	STATE_INITIAL,	0
.equ	STATE_AARCH32,	1
.equ	STATE_AARCH64,	2

/* Saved Program Status Register (EL2) */
.equ	SPSR_EL2_A,		1 << 8	/* SError interrupt mask */
.equ	SPSR_EL2_I,		1 << 7	/* IRQ interrupt mask */
.equ	SPSR_EL2_F,		1 << 6	/* FIQ interrupt mask */
.equ	SPSR_EL2_AIF,		SPSR_EL2_A | SPSR_EL2_I | SPSR_EL2_F
.equ	SPSR_EL2_AARCH32_SVC,	0b10011		/* aarch32 supervisor mode */

/* Counter-Timer Hypervisor Control Register (EL2) */
.equ	CNTHCTL_EL2_EL1PCEN,	1 << 1	/* allow EL0/EL1 timer access */
.equ	CNTHCTL_EL2_EL1PCTEN,	1 << 0	/* allow EL0/EL1 counter access */

/* Architectural Feature Trap Register (EL2) */
.equ	CPTR_EL2_RES1,		1 << 13 | 1 << 12 | 1 << 9 | 1 << 8 | 0xff

/*
 * HYP entry point. This is called by TZ to initialize the CPU EL2 states
 * on initial boot-up and whenever a CPU core is turned back on after a power
 * collapse (e.g. because of SMP or CPU idle).
 *   Parameters: x0 = EL1 entry address, x1 = STATE_AARCH32/STATE_AARCH64
 *               x3 = Something? Seems to be always zero...
 */
.global _start
_start:
	mov	lr, x0		/* save entry address to link register */

	/*
	 * Register allocation:
	 *   x0 = temporary register
	 *   x1 = STATE_AARCH32/STATE_AARCH64
	 *   x2 = execution_state value
	 *   x3 = temporary register
	 *   lr = bootloader/kernel entry address
	 */
	.macro clrregs
		/* Clear registers used in this function */
		mov	x0, xzr
		mov	x1, xzr
		mov	x2, xzr
		mov	x3, xzr
	.endm

	/* First, figure out if this is the initial boot-up */
	adr	x0, execution_state
	ldrb	w2, [x0]
	cbnz	w2, skip_init
	strb	w1, [x0]	/* set initial execution_state based on x1 */

	/* Bring RPM out of reset */
	mov	x0, 0x1860000	/* GCC_APSS_MISC */
	ldr	w3, [x0]
	and	w3, w3, ~0b1	/* RPM_RESET_REMOVAL */
	str	w3, [x0]

skip_init:
	cmp	x1, STATE_AARCH64
	bne	not_aarch64

	/* Jump to aarch64 directly in EL2! */
	clrregs
	ret

not_aarch64:
	cmp	x1, STATE_AARCH32
	bne	panic		/* invalid state parameter */

	/* aarch32 EL1 setup */
	msr	hcr_el2, xzr	/* EL1 is aarch32 */
	mov	x3, SPSR_EL2_AIF | SPSR_EL2_AARCH32_SVC
	msr	spsr_el2, x3

	/* Allow EL1 to access timer/counter */
	mov	x0, CNTHCTL_EL2_EL1PCEN | CNTHCTL_EL2_EL1PCTEN
	msr	cnthctl_el2, x0
	msr	cntvoff_el2, xzr	/* clear virtual offset */

	/* Disable coprocessor traps */
	mov	x3, CPTR_EL2_RES1
	msr	cptr_el2, x3
	msr	hstr_el2, xzr

	/* Configure EL1 return address and return! */
	msr	elr_el2, lr
	clrregs
	eret

panic:
	b	panic

.data
execution_state:
	.byte	0
