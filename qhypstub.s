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

/* SMC Calling Convention return codes */
.equ	SMCCC_NOT_SUPPORTED,		-1
.equ	SMCCC_INVALID_PARAMETER,	-3

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
	b	not_aarch64	/* FIXME */

skip_init:
	/* FIXME: Why is this always aarch32 suddenly? */
	/*cmp	x1, STATE_AARCH64
	bne	not_aarch64*/

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

	/* Set exception vector table for initial execution state switch */
	adr	x0, el2_vector_table
	msr	vbar_el2, x0

	/* Configure EL1 return address and return! */
	msr	elr_el2, lr
	clrregs
	eret

panic:
	b	panic

hvc32:
	/*
	 * Right now we only handle one SMC/HVC call here, which is used to
	 * jump to a aarch64 kernel from a aarch32 bootloader. The difference
	 * is that we will try entering the kernel in EL2, while TZ/SMC
	 * would enter in EL1.
	 */
	mov	w15, 0x2000000	/* SMC32/HVC32 SiP Service Call */
	movk	w15, 0x10f	/* something like "jump to kernel in aarch64" */
	cmp	w0, w15
	beq	hvc32_jump_aarch64
	mov	w0, SMCCC_NOT_SUPPORTED
	eret

hvc32_jump_aarch64:
	/* Jump to aarch64 in EL2 based on struct el1_system_param in LK scm.h */
	cmp	w1, 0x12	/* MAKE_SCM_ARGS(0x2, SMC_PARAM_TYPE_BUFFER_READ) */
	bne	hvc_invalid
	cmp	w3, 10*8	/* size of struct, x0-x7 + lr * uint64_t */
	bne	hvc_invalid

	/* Load all registers and jump here directly in EL2! */
	mov	w8, w2
	ldp	x0, x1, [x8]
	ldp	x2, x3, [x8, 1*2*8]
	ldp	x4, x5, [x8, 2*2*8]
	ldp	x6, x7, [x8, 3*2*8]
	ldp	x8, lr, [x8, 4*2*8]
	ret

hvc_invalid:
	mov	w0, SMCCC_INVALID_PARAMETER
	eret

/* EL2 exception vectors (written to VBAR_EL2) */
.section .text.vectab
.macro excvec label
	/* Each exception vector is 32 instructions long, so 32*4 = 2^7 bytes */
	.align 7
\label:
.endm

el2_vector_table:
	excvec	el2_sp0_sync
	b	panic
	excvec	el2_sp0_irq
	b	panic
	excvec	el2_sp0_fiq
	b	panic
	excvec	el2_sp0_serror
	b	panic

	excvec	el2_sp2_sync
	b	panic
	excvec	el2_sp2_irq
	b	panic
	excvec	el2_sp2_fiq
	b	panic
	excvec	el2_sp2_serror
	b	panic

	excvec	el1_aarch64_sync
	b	panic
	excvec	el1_aarch64_irq
	b	panic
	excvec	el1_aarch64_fiq
	b	panic
	excvec	el1_aarch64_serror
	b	panic

	excvec	el1_aarch32_sync
	mrs	x15, esr_el2
	lsr	x15, x15, 26	/* shift to exception class */
	cmp	x15, 0b010010	/* HVC instruction? */
	beq	hvc32
	b	panic
	excvec	el1_aarch32_irq
	b	panic
	excvec	el1_aarch32_fiq
	b	panic
	excvec	el1_aarch32_serror
	b	panic

	excvec	el2_vector_table_end

.data
execution_state:
	.byte	0
