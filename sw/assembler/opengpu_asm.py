#!/usr/bin/env python3
"""
OpenGPU Assembler - converts .asm to machine code hex files.

Instruction formats (32-bit):
  R-Type: [31:26] opcode | [25:21] rd | [20:16] rs1 | [15:11] rs2 | [10:0] func
  I-Type: [31:26] opcode | [25:21] rd | [20:16] rs1 | [15:0] imm16
  S-Type: [31:26] opcode | [25:21] rs2 | [20:16] rs1 | [15:0] offset
  B-Type: [31:26] opcode | [25:21] cond | [20:16] rs1 | [15:0] offset
  U-Type: [31:26] opcode | [25:21] rd | [20:0] imm21

Usage: python opengpu_asm.py input.asm [output.hex]
"""

import sys
import re
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

OPCODES = {
    'ADD': 0x00, 'ADDI': 0x01, 'SUB': 0x02,
    'MUL': 0x03, 'MULH': 0x04, 'DIV': 0x05,
    'DIVU': 0x06, 'REM': 0x07, 'REMU': 0x08,
    'AND': 0x10, 'ANDI': 0x11, 'OR': 0x12,
    'ORI': 0x13, 'XOR': 0x14, 'XORI': 0x15,
    'NOT': 0x16,
    'SLL': 0x17, 'SLLI': 0x18, 'SRL': 0x19,
    'SRLI': 0x1A, 'SRA': 0x1B, 'SRAI': 0x1C,
    # FPU instructions (0x20-0x2F)
    'FADD': 0x20, 'FSUB': 0x21, 'FMUL': 0x22, 'FDIV': 0x23,
    'FMADD': 0x24, 'FMSUB': 0x25, 'FSQRT': 0x26,
    'FABS': 0x27, 'FNEG': 0x28, 'FMIN': 0x29, 'FMAX': 0x2A,
    'FCVTWS': 0x2B, 'FCVTSW': 0x2C,
    'FCMPEQ': 0x2D, 'FCMPLT': 0x2E, 'FCMPLE': 0x2F,
    'SLT': 0x40, 'SLTI': 0x41, 'SLTU': 0x42,
    'SLTIU': 0x43, 'SEQ': 0x44, 'SNE': 0x45,
    'SGE': 0x46, 'SGEU': 0x47,
    'LW': 0x30, 'LH': 0x31, 'LHU': 0x32,
    'LB': 0x33, 'LBU': 0x34, 'SW': 0x35,
    'SH': 0x36, 'SB': 0x37,
    'BEQ': 0x50, 'BNE': 0x51, 'BLT': 0x52,
    'BGE': 0x53, 'BLTU': 0x54, 'BGEU': 0x55,
    'JAL': 0x56, 'JALR': 0x57,
    'RET': 0x58,
    'LUI': 0x69, 'AUIPC': 0x6A,
    'NOP': None, 'MV': None, 'LI': None, 'J': None,
}

R_TYPE = {'ADD', 'SUB', 'MUL', 'MULH', 'DIV', 'DIVU', 'REM', 'REMU',
          'AND', 'OR', 'XOR', 'NOT', 'SLL', 'SRL', 'SRA',
          'SLT', 'SLTU', 'SEQ', 'SNE', 'SGE', 'SGEU'}
I_TYPE = {'ADDI', 'ANDI', 'ORI', 'XORI', 'SLLI', 'SRLI', 'SRAI', 'SLTI', 'SLTIU', 'JALR'}
MEM_LOAD = {'LW', 'LH', 'LHU', 'LB', 'LBU'}
MEM_STORE = {'SW', 'SH', 'SB'}
B_TYPE = {'BEQ', 'BNE', 'BLT', 'BGE', 'BLTU', 'BGEU'}
U_TYPE = {'LUI', 'AUIPC', 'JAL'}
CTRL_TYPE = {'RET'}
# FPU instruction sets
FPU_R2 = {'FADD', 'FSUB', 'FMUL', 'FDIV', 'FMIN', 'FMAX', 'FCMPEQ', 'FCMPLT', 'FCMPLE'}  # 2 operands
FPU_R1 = {'FABS', 'FNEG', 'FSQRT', 'FCVTWS', 'FCVTSW'}  # 1 operand
FPU_R3 = {'FMADD', 'FMSUB'}  # 3 operands (rd = rs1 * rs2 + rs3)

REGISTERS = {
    'X0': 0, 'ZERO': 0,
    'X1': 1, 'THREADIDX': 1, 'TID': 1,
    'X2': 2, 'BLOCKIDX': 2, 'BID': 2,
    'X3': 3, 'BLOCKDIM': 3, 'BDIM': 3,
    'X4': 4, 'GRIDDIM': 4, 'GDIM': 4,
    'X5': 5, 'WARPIDX': 5, 'WID': 5,
    'X6': 6, 'LANEIDX': 6, 'LID': 6,
    **{f'X{i}': i for i in range(7, 32)},
    'T0': 7, 'T1': 8, 'T2': 9, 'T3': 10, 'T4': 11,
    'T5': 12, 'T6': 13, 'T7': 14, 'T8': 15,
}


@dataclass
class Instruction:
    line_num: int
    address: int
    mnemonic: str
    operands: List[str]
    label: Optional[str] = None


class Assembler:
    def __init__(self):
        self.labels: Dict[str, int] = {}
        self.instructions: List[Instruction] = []
        self.current_address = 0

    def parse_register(self, reg_str: str) -> int:
        reg_str = reg_str.upper().strip()
        if reg_str in REGISTERS:
            return REGISTERS[reg_str]
        raise ValueError(f"Unknown register: {reg_str}")

    def parse_immediate(self, imm_str: str, labels: Dict[str, int] = None,
                       current_addr: int = 0, relative: bool = False) -> int:
        imm_str = imm_str.strip()
        if labels and imm_str in labels:
            return labels[imm_str] - current_addr if relative else labels[imm_str]
        try:
            if imm_str.startswith('0x') or imm_str.startswith('0X'):
                return int(imm_str, 16)
            elif imm_str.startswith('0b') or imm_str.startswith('0B'):
                return int(imm_str, 2)
            return int(imm_str)
        except ValueError:
            raise ValueError(f"Cannot parse immediate: {imm_str}")

    def parse_memory_operand(self, operand: str) -> Tuple[int, int]:
        match = re.match(r'(-?\d+)?\((\w+)\)', operand.strip())
        if not match:
            raise ValueError(f"Invalid memory operand: {operand}")
        offset = int(match.group(1) or '0')
        reg = self.parse_register(match.group(2))
        return offset, reg

    def encode_r_type(self, opcode: int, rd: int, rs1: int, rs2: int = 0) -> int:
        return (opcode << 26) | (rd << 21) | (rs1 << 16) | (rs2 << 11)

    def encode_i_type(self, opcode: int, rd: int, rs1: int, imm: int) -> int:
        return (opcode << 26) | (rd << 21) | (rs1 << 16) | (imm & 0xFFFF)

    def encode_s_type(self, opcode: int, rs2: int, rs1: int, offset: int) -> int:
        return (opcode << 26) | (rs2 << 21) | (rs1 << 16) | (offset & 0xFFFF)

    def encode_b_type(self, opcode: int, rs1: int, rs2: int, offset: int) -> int:
        return (opcode << 26) | (rs2 << 21) | (rs1 << 16) | (offset & 0xFFFF)

    def encode_u_type(self, opcode: int, rd: int, imm: int) -> int:
        return (opcode << 26) | (rd << 21) | (imm & 0x1FFFFF)

    def first_pass(self, lines: List[str]):
        self.current_address = 0
        for line_num, line in enumerate(lines, 1):
            line = line.split('#')[0].strip()
            if not line:
                continue
            if ':' in line:
                parts = line.split(':')
                self.labels[parts[0].strip()] = self.current_address
                line = ':'.join(parts[1:]).strip()
                if not line:
                    continue
            if line.startswith('.'):
                continue
            self.current_address += 4

    def second_pass(self, lines: List[str]) -> List[int]:
        machine_code = []
        self.current_address = 0
        for line_num, line in enumerate(lines, 1):
            line = line.split('#')[0].strip()
            if not line:
                continue
            if ':' in line:
                line = ':'.join(line.split(':')[1:]).strip()
                if not line:
                    continue
            if line.startswith('.'):
                continue
            try:
                code = self.assemble_instruction(line, line_num)
                machine_code.append(code)
                self.current_address += 4
            except Exception as e:
                print(f"Error at line {line_num}: {line}\n  {e}")
                raise
        return machine_code

    def assemble_instruction(self, line: str, line_num: int) -> int:
        parts = line.replace(',', ' ').split()
        mnemonic = parts[0].upper()
        operands = parts[1:] if len(parts) > 1 else []

        # Pseudo-instructions
        if mnemonic == 'NOP':
            return self.encode_i_type(OPCODES['ADDI'], 0, 0, 0)
        if mnemonic == 'MV':
            return self.encode_i_type(OPCODES['ADDI'], self.parse_register(operands[0]),
                                      self.parse_register(operands[1]), 0)
        if mnemonic == 'LI':
            rd = self.parse_register(operands[0])
            imm = self.parse_immediate(operands[1])
            if -32768 <= imm <= 32767:
                return self.encode_i_type(OPCODES['ADDI'], rd, 0, imm)
            raise ValueError(f"LI immediate too large: {imm}")
        if mnemonic == 'J':
            offset = self.parse_immediate(operands[0], self.labels, self.current_address, relative=True)
            return self.encode_u_type(OPCODES['JAL'], 0, offset)

        if mnemonic not in OPCODES:
            raise ValueError(f"Unknown instruction: {mnemonic}")
        opcode = OPCODES[mnemonic]

        if mnemonic in R_TYPE:
            if mnemonic == 'NOT':
                return self.encode_r_type(opcode, self.parse_register(operands[0]),
                                          self.parse_register(operands[1]), 0)
            return self.encode_r_type(opcode, self.parse_register(operands[0]),
                                      self.parse_register(operands[1]),
                                      self.parse_register(operands[2]))

        if mnemonic in I_TYPE:
            return self.encode_i_type(opcode, self.parse_register(operands[0]),
                                      self.parse_register(operands[1]),
                                      self.parse_immediate(operands[2], self.labels))

        if mnemonic in MEM_LOAD:
            rd = self.parse_register(operands[0])
            offset, rs1 = self.parse_memory_operand(operands[1])
            return self.encode_i_type(opcode, rd, rs1, offset)

        if mnemonic in MEM_STORE:
            rs2 = self.parse_register(operands[0])
            offset, rs1 = self.parse_memory_operand(operands[1])
            return self.encode_s_type(opcode, rs2, rs1, offset)

        if mnemonic in B_TYPE:
            rs1 = self.parse_register(operands[0])
            rs2 = self.parse_register(operands[1])
            offset = self.parse_immediate(operands[2], self.labels, self.current_address, relative=True)
            return self.encode_b_type(opcode, rs1, rs2, offset)

        if mnemonic in U_TYPE:
            if mnemonic == 'JAL':
                rd = self.parse_register(operands[0])
                offset = self.parse_immediate(operands[1], self.labels, self.current_address, relative=True)
                return self.encode_u_type(opcode, rd, offset)
            rd = self.parse_register(operands[0])
            imm = self.parse_immediate(operands[1], self.labels)
            return self.encode_u_type(opcode, rd, imm)

        if mnemonic in CTRL_TYPE:
            return opcode << 26

        # FPU 2-operand (rd, rs1, rs2)
        if mnemonic in FPU_R2:
            return self.encode_r_type(opcode, self.parse_register(operands[0]),
                                      self.parse_register(operands[1]),
                                      self.parse_register(operands[2]))

        # FPU 1-operand (rd, rs1)
        if mnemonic in FPU_R1:
            return self.encode_r_type(opcode, self.parse_register(operands[0]),
                                      self.parse_register(operands[1]), 0)

        # FPU 3-operand (rd, rs1, rs2, rs3) - rs3 encoded in func field [10:6]
        if mnemonic in FPU_R3:
            rd = self.parse_register(operands[0])
            rs1 = self.parse_register(operands[1])
            rs2 = self.parse_register(operands[2])
            rs3 = self.parse_register(operands[3])
            # rs3 goes in bits [10:6]
            return (opcode << 26) | (rd << 21) | (rs1 << 16) | (rs2 << 11) | (rs3 << 6)

        raise ValueError(f"Unhandled instruction: {mnemonic}")

    def assemble(self, source: str) -> List[int]:
        lines = source.split('\n')
        self.first_pass(lines)
        return self.second_pass(lines)

    def to_hex(self, machine_code: List[int]) -> str:
        return '\n'.join(f'{code:08x}' for code in machine_code)

    def to_memh(self, machine_code: List[int]) -> str:
        lines = ['// OpenGPU machine code', '']
        for i, code in enumerate(machine_code):
            lines.append(f'{code:08x}  // addr {i*4:04x}')
        return '\n'.join(lines)


def main():
    if len(sys.argv) < 2:
        print("Usage: python opengpu_asm.py input.asm [output.hex]")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else input_file.replace('.asm', '.hex')

    with open(input_file, 'r') as f:
        source = f.read()

    asm = Assembler()
    try:
        machine_code = asm.assemble(source)
        with open(output_file, 'w') as f:
            f.write(asm.to_memh(machine_code))
        print(f"Assembled {len(machine_code)} instructions to {output_file}")
        if asm.labels:
            print("\nLabels:")
            for label, addr in asm.labels.items():
                print(f"  {label}: 0x{addr:04x}")
    except Exception as e:
        print(f"Assembly failed: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()
