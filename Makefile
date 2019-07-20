all:
	@nasm -I src/ -f bin -o puny src/entry.asm
	@chmod 750 ./puny
	@wc -c ./puny
