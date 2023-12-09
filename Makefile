.PHONY:  all clean emu

all:  shell.prg ext-command.prg neofetch.prg time.prg

clean:
	rm -f *.prg *.asm *.vice-*

emu:  all
	mcopy -D o shell.prg x:SHELL
	mcopy -D o ext-command.prg x:SHELL-CMDS/EXT-COMMAND
	mcopy -D o neofetch.prg x:SHELL-CMDS/NEOFETCH
	mcopy -D o time.prg x:SHELL-CMDS/TIME
	mcopy -D o time.prg x:SHELL-CMDS/DATE
	mcopy -D o motd.txt x:SHELL-CMDS/motd.txt
	x16emu -sdcard ~/cx16sdcard.img -scale 2 -quality best -run -prg shell.prg

shell.prg: src/shell.p8 src/errors.p8 src/disk_commands.p8 src/misc_commands.p8
	p8compile $< -target cx16

ext-command.prg: externalcommands/example/ext-command.p8
	p8compile $< -target cx16

neofetch.prg: externalcommands/neofetch/neofetch.p8
	p8compile $< -target cx16

time.prg: externalcommands/example/time.p8
	p8compile $< -target cx16
