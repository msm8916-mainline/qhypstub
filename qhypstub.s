/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (C) 2021 Stephan Gerhold
 *
 * Based on the "ARM Architecture Reference Manual for Armv8-A"
 * and EL2/EL1 initialization sequences adapted from Linux and U-Boot.
 */
.cpu	cortex-a53

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
 * HYP entry point
 */
.global _start
_start:
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

	/* Configure (hard-coded) EL1 return address and return! */
	mov	x0, 0x8f600000
	msr	elr_el2, x0
	eret
