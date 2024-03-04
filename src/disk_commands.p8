%import textio
%import string
%import diskio
%import conv
%import errors
%encoding iso

disk_commands {

    uword[] commands_table = [
        "ls", &cmd_ls,
        "dir", &cmd_ls,
        "cat", &cmd_cat,
        "type", &cmd_cat,
        "rm", &cmd_rm,
        "del", &cmd_rm,
        "mv", &cmd_rename,
        "ren", &cmd_rename,
        "cp", &cmd_copy,
        "copy", &cmd_copy,
        "cd", &cmd_cd,
        "pwd", &cmd_pwd,
        "mkdir", &cmd_mkdir,
        "rmdir", &cmd_rmdir,
        "relabel", &cmd_relabel,
        "drive", &cmd_drive
    ]

    sub recognized(str cmdword, ubyte length) -> uword {
        ubyte idx
        for idx in 0 to len(commands_table)-1 step 2 {
            if string.compare(cmdword, commands_table[idx])==0
                return commands_table[idx+1]
        }
        return 0
    }

    sub cmd_ls() -> bool {
        ubyte num_files = 0
        if diskio.lf_start_list(main.command_arguments_ptr) {
            txt.color(main.COLOR_HIGHLIGHT)
            txt.print(" Blocks  Filename\r")
            txt.color(main.COLOR_NORMAL)
            while diskio.lf_next_entry() {
                num_files++
                txt.spc()
                txt.spc()
                if diskio.list_filetype == petscii:"dir"
                    txt.print("[dir]")
                else
                    main.print_uw_right(diskio.list_blocks)
                txt.spc()
                txt.spc()
                txt.print(diskio.list_filename)
                txt.nl()
                if cbm.STOP2() {
                    txt.color(main.COLOR_HIGHLIGHT)
                    txt.print("Break\r")
                    txt.color(main.COLOR_NORMAL)
                    break
                }
            }
            diskio.lf_end_list()
            if num_files == 0 {
                txt.color(main.COLOR_HIGHLIGHT)
                txt.print("No files\r")
                txt.color(main.COLOR_NORMAL)
            }
            return true
        }
        err.set("IO error")
        return false
    }

    sub cmd_rm() -> bool {
        if main.command_arguments_size==0 {
            err.set("Missing arg: filename")
            return false
        }
        void string.find(main.command_arguments_ptr, '*')
        if_cs {
            ;txt.color(main.COLOR_HIGHLIGHT)
            ;txt.print("Has * wildcard. Sure y/n? ")
            ;txt.color(main.COLOR_NORMAL)
            ;ubyte answer = c64.CHRIN()
            ;txt.nl()
            ;if answer == 'y' {
            ;    err.set("TODO custom pattern matching with * wildcard") ; TODO
            ;    return false
            ;}
            err.set("Refused to act on * wildcard")
            return false
        }
        diskio.delete(main.command_arguments_ptr)
        print_disk_status()
        return true
    }

    sub cmd_rename() -> bool {
        if main.command_arguments_size==0 {
            err.set("Missing args: oldfilename newfilename")
            return false
        }

        uword newfilename
        ubyte space_idx = string.find(main.command_arguments_ptr, ' ')
        if_cs {
            newfilename = main.command_arguments_ptr + space_idx + 1
            main.command_arguments_ptr[space_idx] = 0
            diskio.rename(main.command_arguments_ptr, newfilename)
            print_disk_status()
            return true
        } else {
            err.set("Missing args: oldfilename newfilename")
            return false
        }
    }

    sub print_disk_status() {
        txt.color(main.COLOR_HIGHLIGHT)
        txt.print(diskio.status())
        txt.color(main.COLOR_NORMAL)
        txt.nl()
    }

    sub cmd_cat() -> bool {
        if main.command_arguments_size==0 {
            err.set("Missing arg: filename")
            return false
        }

        if diskio.f_open(main.command_arguments_ptr) {
            uword line = 0
            repeat {
                void diskio.f_readline(main.command_line)
                line++
                txt.color(main.COLOR_HIGHLIGHT)
                txt.print_uw(line)
                txt.column(5)
                txt.print(": ")
                txt.color(main.COLOR_NORMAL)
                txt.print(main.command_line)
                txt.nl()
                if cbm.READST() & 64 !=0 {
                    break
                }
                if cbm.STOP2() {
                    err.set("break")
                    break
                }
            }
            diskio.f_close()
        } else {
            err.set(diskio.status())
        }
        return true
    }

    sub cmd_pwd() -> bool {
        if main.command_arguments_size!=0 {
            err.set("Has no args")
            return false
        }
        txt.color(main.COLOR_HIGHLIGHT)
        txt.print("Drive number: ")
        txt.color(main.COLOR_NORMAL)
        txt.print_ub(diskio.drivenumber)
        txt.nl()

        ; special X16 dos command to only return the current path in the entry list
        ; pull request: https://github.com/commanderx16/x16-rom/pull/373
        ; note: I'm also using *=d filter to not get a screen full of nonsense when
        ; you run this code on a rom version that doesn't yet have the $=c command.
        cbm.SETNAM(7, petscii:"$=c:*=d")
        cbm.SETLFS(12, diskio.drivenumber, 0)
        ubyte status = 1
        void cbm.OPEN()          ; open 12,8,0,"$=c:*=d"
        if_cs
            goto io_error
        void cbm.CHKIN(12)        ; use #12 as input channel
        if_cs
            goto io_error

        while cbm.CHRIN()!='"' {
            ; skip up to entry name
        }

        bool first_line_diskname=true
        status = cbm.READST()
        while status==0 {
            cx16.r0 = &main.command_line
            repeat {
                @(cx16.r0) = cbm.CHRIN()
                if @(cx16.r0)==0
                    break
                cx16.r0++
            }
            process_line(main.command_line, first_line_diskname)
            first_line_diskname=false
            while cbm.CHRIN()!='"' and status==0 {
                status = cbm.READST()
                ; skipping up to next entry name
            }
        }
        status = cbm.READST()

io_error:
        cbm.CLRCHN()        ; restore default i/o devices
        cbm.CLOSE(12)

        if status!=0 and status & $40 == 0  {          ; bit 6=end of file
            err.set("IO error")
            return false
        }

        txt.nl()
        return true

        sub process_line(uword lineptr, bool diskname) {
            if diskname {
                txt.color(main.COLOR_HIGHLIGHT)
                txt.print("Disk name: ")
                txt.color(main.COLOR_NORMAL)
            }
            repeat {
                cx16.r0L=@(lineptr)
                if cx16.r0L=='"'
                    break
                txt.chrout(cx16.r0L)
                lineptr++
            }
            if diskname {
                txt.color(main.COLOR_HIGHLIGHT)
                txt.print("\rCurrent dir: ")
                txt.color(main.COLOR_NORMAL)
            } else if @(lineptr-1)!='/' {
                txt.color(main.COLOR_HIGHLIGHT)
                txt.print(" in ")
                txt.color(main.COLOR_NORMAL)
            }
        }
    }

    sub cmd_mkdir() -> bool {
        if main.command_arguments_size==0 {
            err.set("Missing arg: dirname")
            return false
        }
        diskio.mkdir(main.command_arguments_ptr)
        print_disk_status()
        return true
    }

    sub cmd_cd() -> bool {
        if main.command_arguments_size==0 {
            err.set("Missing arg: dirname")
            return false
        }
        diskio.chdir(main.command_arguments_ptr)
        print_disk_status()
        return true
    }

    sub cmd_rmdir() -> bool {
        if main.command_arguments_size==0 {
            err.set("Missing arg: dirname")
            return false
        }

        void string.find(main.command_arguments_ptr, '*')
        if_cs {
            err.set("Refused to act on * wildcard")
            return false
        }

        diskio.rmdir(main.command_arguments_ptr)
        print_disk_status()
        return true
    }

    sub cmd_relabel() -> bool {
        if main.command_arguments_size==0 {
            err.set("Missing arg: diskname")
            return false
        }
        diskio.relabel(main.command_arguments_ptr)
        print_disk_status()
        return true
    }

    sub cmd_copy() -> bool {
        if main.command_arguments_size==0 {
            err.set("Missing args: oldfilename newfilename")
            return false
        }

        uword newfilename
        ubyte space_idx = string.find(main.command_arguments_ptr, ' ')
        if_cs {
            newfilename = main.command_arguments_ptr + space_idx + 1
            main.command_arguments_ptr[space_idx] = 0
            diskio.list_filename[0] = petscii:'c'
            diskio.list_filename[1] = petscii:':'
            ubyte length = string.copy(newfilename, &diskio.list_filename+2)
            diskio.list_filename[length+2] = petscii:'='
            void string.copy(main.command_arguments_ptr, &diskio.list_filename+length+3)
            diskio.send_command(diskio.list_filename)
            print_disk_status()
            return true
        } else {
            err.set("Missing args: oldfilename newfilename")
            return false
        }
    }

    sub cmd_drive() -> bool {
        if main.command_arguments_size==0 {
            err.set("Missing arg: drive number")
            return false
        }

        ubyte nr = conv.str2ubyte(main.command_arguments_ptr)

        when nr {
            8, 9 -> {
                txt.print("Switching drive.\r")
                diskio.drivenumber = nr
                main.command_arguments_size = 0
                return cmd_pwd()
            }
            else -> {
                err.set("Invalid drive number")
                return false
            }
        }
    }

}
