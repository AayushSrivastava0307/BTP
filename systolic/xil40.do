if {[batch_mode]} { onerror {quit -f -code 1} }
catch {quit -sim}
vsim -voptargs=+acc -c +NFRAMES=40 work_xil.tb
run -all
if {[batch_mode]} { quit -f }
