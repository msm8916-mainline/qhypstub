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

/* Hypervisor Configuration Register (EL2) */
.equ	HCR_EL2_RW,	1 << 31		/* register width, EL1 is aarch64 */
.equ	HCR_EL2_VM,	1 << 0		/* enable stage 2 address translation */

/* Saved Program Status Register (EL2) */
.equ	SPSR_EL2_AARCH64_D,	1 << 9	/* debug exception mask (aarch64) */
.equ	SPSR_EL2_A,		1 << 8	/* SError interrupt mask */
.equ	SPSR_EL2_I,		1 << 7	/* IRQ interrupt mask */
.equ	SPSR_EL2_F,		1 << 6	/* FIQ interrupt mask */
.equ	SPSR_EL2_AIF,		SPSR_EL2_A | SPSR_EL2_I | SPSR_EL2_F
.equ	SPSR_EL2_AARCH32_SVC,	0b10011		/* aarch32 supervisor mode */
.equ	SPSR_EL2_AARCH64_EL1H,	0b00101		/* aarch64 EL1h mode */

/* Counter-Timer Hypervisor Control Register (EL2) */
.equ	CNTHCTL_EL2_EL1PCEN,	1 << 1	/* allow EL0/EL1 timer access */
.equ	CNTHCTL_EL2_EL1PCTEN,	1 << 0	/* allow EL0/EL1 counter access */

/* Architectural Feature Trap Register (EL2) */
.equ	CPTR_EL2_RES1,		1 << 13 | 1 << 12 | 1 << 9 | 1 << 8 | 0xff

/* Virtualization Translation Control Register */
.equ	VTCR_EL2_RES1,		1 << 31
	/* 32-bit physical/translated address, 4 KB granule, start at level 1 */
.equ	VTCR_EL2_32BIT_4KB_L1,	0 << 16 | 0 << 14 | 1 << 6 | 32

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

	/*
	 * Overall, we need to handle 5 different scenarios here... :S
	 *   Initial boot:
	 *     1. To aarch64 bootloader/kernel in EL2
	 *     2. To aarch32 bootloader/kernel in EL1
	 *   SMP / boot after power collapse:
	 *     3. aarch64 (EL2)
	 *     4. aarch32 (EL1)
	 *     5. aarch64 (EL1) - only if main CPU has booted aarch64 in EL1
	 *        because the bootloader used the SMC call instead of HVC call
	 *        for the aarch64 state switch
	 */

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

	/* Set exception vector table for initial execution state switch */
	adr	x0, el2_vector_table
	msr	vbar_el2, x0

	/*
	 * Special case for loading initial bootloader in aarch64 state.
	 * There is a bug in the TZ PSCI implementation that starts all other
	 * CPU cores in aarch32 state unless we invoke its SMC call to switch
	 * to aarch64 state. So we need to do that here. See hvc32_jump_aarch64.
	 */
	cmp	x1, STATE_AARCH64
	beq	bootup_smc_switch_aarch64
	b	not_aarch64

skip_init:
	cmp	x1, STATE_AARCH64
	bne	not_aarch64

	/*
	 * Check if we ever did a state switch to aarch64 (either by directly
	 * jumping to a aarch64 bootloader, or using the HVC call).
	 * If not, the state switch to aarch64 happened without involving us
	 * (probably through the SMC call in TZ), which means that the main CPU
	 * booted in EL1. In that case, we should also boot the other cores in
	 * EL1 to avoid confusion (e.g. "CPUs started in inconsistent modes"
	 * warning in Linux).
	 */
	cmp	w2, STATE_AARCH64
	bne	aarch64_el1

	/* Everything seems to run directly in EL2, so jump there directly! */
	clrregs
	ret

aarch64_el1:
	/* aarch64 EL1 setup */
	mov	x0, HCR_EL2_RW	/* EL1 is aarch64 */
	msr	hcr_el2, x0
	mov	x3, SPSR_EL2_AARCH64_D | SPSR_EL2_AIF | SPSR_EL2_AARCH64_EL1H
	b	prepare_eret

not_aarch64:
	cmp	x1, STATE_AARCH32
	bne	panic		/* invalid state parameter */

	/* aarch32 EL1 setup */
	msr	hcr_el2, xzr	/* EL1 is aarch32 */
	mov	x3, SPSR_EL2_AIF | SPSR_EL2_AARCH32_SVC

prepare_eret:
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
	beq	smc_switch_aarch64
	mov	w0, SMCCC_NOT_SUPPORTED
	eret

bootup_smc_switch_aarch64:
	/* Set up SMC call to make TZ aware of the state switch to aarch64 */
	mov	x0, 0x2000000	/* SMC32/HVC32 SiP Service Call */
	movk	x0, 0x10f	/* something like "jump to kernel in aarch64" */
	mov	x1, 0x12	/* MAKE_SCM_ARGS(0x2, SMC_PARAM_TYPE_BUFFER_READ) */
	adr	x2, scm_jump_aarch64_args
	mov	x3, scm_jump_aarch64_args_end - scm_jump_aarch64_args
	str	lr, [x2, scm_jump_aarch64_args_end - scm_jump_aarch64_args - 8]
	/* Fallthrough */

smc_switch_aarch64:
	/*
	 * Theoretically we could just jump to the entry point directly here in
	 * EL2. However, in practice this does not work correctly. It seems like
	 * TZ/PSCI records if we ever did the SMC call to switch to aarch64 state.
	 * If we bypass it when booting aarch64 kernels, the other CPU cores
	 * will be brought up in aarch32 state instead of aarch64 later.
	 *
	 * So, we do need to use the SMC call to switch to aarch64.
	 * Unfortunately, TZ does not involve the hypervisor when switching states.
	 * It modifies our HCR_EL2 register to enable aarch64, and returns in EL1
	 * even if we do the SMC call here from EL2.
	 *
	 * So, somehow we need to jump back to EL2 immediately after the state
	 * switch. The way we do this here is by temporarily activating stage 2
	 * address translation (i.e. the way to protect hypervisor memory).
	 * We don't bother setting up a valid translation table - the only goal
	 * is to cause an Instruction Abort immediately after the state switch.
	 */

	/* Setup invalid address translation table configuration */
	mov	x15, VTCR_EL2_RES1
	movk	x15, VTCR_EL2_32BIT_4KB_L1
	msr	vtcr_el2, x15
	mov	x15, 1 << 32	/* >= 2^32 to cause Address Size Fault */
	msr	vttbr_el2, x15

	/* Enable stage 2 address translation */
	mov	x15, HCR_EL2_VM
	msr	hcr_el2, x15

	/* Let TZ switch to aarch64 and return to EL1 */
	smc	0

	/*
	 * Something went wrong. Maybe parameter validation?
	 * Disable stage 2 address translation again and return to EL1.
	 */
	msr	hcr_el2, xzr
	eret

finish_smc_switch_aarch64:
	/*
	 * We get here once TZ has switched EL1 to aarch64 execution state
	 * and EL1 ran into the Instruction Abort.
	 *
	 * First, cleanup some EL2 configuration registers. This should not
	 * be necessary since the next bootloader/kernel/... should re-initialize
	 * these. However, not clearing HCR_EL2 causes reboots with U-Boot
	 * at least for some weird reason. I guess it doesn't hurt :)
	 */
	msr	hcr_el2, xzr
	msr	vbar_el2, xzr

	/* Record that aarch64 will run in EL2 from now on */
	adr	x30, execution_state
	mov	w29, STATE_AARCH64
	strb	w29, [x30]
	mov	w29, wzr

	/* Now, simply jump to the entry point directly in EL2! */
	mrs	lr, elr_el2
	ret

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
	mrs	x30, esr_el2
	lsr	x30, x30, 26	/* shift to exception class */
	cmp	x30, 0b100000	/* Instruction Abort from lower EL? */
	beq	finish_smc_switch_aarch64
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

	.align	3	/* 64-bit alignment */
scm_jump_aarch64_args:	/* struct el1_system_param in lk scm.h */
	.quad	0, 0, 0, 0, 0, 0, 0, 0, 0, 0	/* el1_x0-x8,elr */
scm_jump_aarch64_args_end:
