# puny-httpd
One of the tiniest HTTP servers on the planet.

* Currently weighing in at **400 bytes** (ELF binary)
* Written in **x86 ASM** (32-bit, for smaller instructions/addresses)
* **No dependencies**, only Linux syscalls

---

Of course, some corners had to be cut:

* A maximum of only **28 simultaneous connections**.
  * The `fd_set` is a single 32-bit integer. This avoids loops to scan/manipulate the bit set.
* **No directory indexes**
* **No error checking** on syscalls, it assumes `bind`, `listen` and `accept` just work
* **Very crude request parsing**:
  * Headers are accepted but ignored
  * The request must:
    * start with `GET /` (there's no POST, no HEAD, no PUT, not even absolute URLs)
    * not contain `/.` (oh look, a security feature!)
* **512 MiB of memory**:
  * Each connection has a 16 MiB request buffer. The address 0x??000000 was cheap to calculate.
* **The code is writable and data is executable**. The ELF header loads code and data in the same memory section. This is extremely bad practice, but it saves 32 bytes!

## Requirements

NASM to assemble the source, and any Linux >= 2.2 to run the binary.

## Usage

    $ make
    $ ./puny

The server runs on port 12345 by default. Edit `sin_port` in [data.asm](src/data.asm) to change this.

## DISCLAIMER

This is obviously a toy. Don't expose it to a public network, don't run it as root.
