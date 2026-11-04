if {[batch_mode]} { onerror {quit -f -code 1} }
catch {quit -sim}
vsim -voptargs=+acc -c +NFRAMES=3 work.tb
foreach s {conv1_ready pooling1_ready conv2_ready pooling2_ready fc1_ready fc2_ready fc3_ready} {
  when "/tb/lenet/$s == 1'b1" "echo \"M $s \$now\""
}
when {/tb/lenet/conv1_go == 1'b1} { echo "M frame_go $now" }
run -all
if {[batch_mode]} { quit -f }
