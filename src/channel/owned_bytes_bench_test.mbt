///|
let owned_bytes_bench_messages_per_producer = 4_096

///|
fn owned_bytes_bench_receive_exact(
  receiver : OwnedBytesReceiver,
  expected : Int,
) -> Int raise SyncError {
  let mut received = 0
  while received < expected {
    match receiver.recv() {
      Some(_) => received += 1
      None => panic()
    }
  }
  received
}

///|
fn owned_bytes_bench_spawn_worker(
  command_receiver : OwnedBytesReceiver,
  data_sender : OwnedBytesSender,
) -> @thread.Thread {
  try! @thread.spawn(fn() raise {
    let payload = Bytes::make(64, b'\x00')
    for ;; {
      match command_receiver.recv() {
        Some(_) =>
          for _ in 0..<owned_bytes_bench_messages_per_producer {
            if !data_sender.send(payload) {
              panic()
            }
          }
        None => break
      }
    }
  })
}

///|
test "bench owned bytes 1p1c 64B" (b : @bench.T) {
  b.bench(name="owned_bytes/1p1c/64B", count=30, fn() {
    let (sender, receiver) = try! owned_bytes_bounded(1_024)
    let worker_sender = try! sender.share()
    let worker = try! @thread.spawn(fn() raise {
      let payload = Bytes::make(64, b'\x00')
      for _ in 0..<owned_bytes_bench_messages_per_producer {
        if !worker_sender.send(payload) {
          panic()
        }
      }
    })
    let received = try! owned_bytes_bench_receive_exact(
      receiver, owned_bytes_bench_messages_per_producer,
    )
    try! worker.join()
    b.keep(received)
  })
}

///|
test "bench owned bytes steady 1p1c 64B" (b : @bench.T) {
  let (command_sender, command_receiver) = try! owned_bytes_bounded(1)
  let (data_sender, data_receiver) = try! owned_bytes_bounded(1_024)
  let worker = owned_bytes_bench_spawn_worker(
    command_receiver,
    data_sender.share(),
  )

  if !command_sender.send(b"warmup") {
    panic()
  }
  ignore(
    owned_bytes_bench_receive_exact(
      data_receiver, owned_bytes_bench_messages_per_producer,
    ),
  )

  b.bench(name="owned_bytes/steady/1p1c/64B", count=30, fn() {
    if !(try! command_sender.send(b"run")) {
      panic()
    }
    b.keep(
      try! owned_bytes_bench_receive_exact(
        data_receiver, owned_bytes_bench_messages_per_producer,
      ),
    )
  })

  command_sender.close()
  try! worker.join()
}

///|
test "bench owned bytes 4p1c 64B" (b : @bench.T) {
  b.bench(name="owned_bytes/4p1c/64B", count=30, fn() {
    let (sender, receiver) = try! owned_bytes_bounded(1_024)
    let workers : Array[@thread.Thread] = []
    for _ in 0..<4 {
      let worker_sender = try! sender.share()
      workers.push(
        try! @thread.spawn(fn() raise {
          let payload = Bytes::make(64, b'\x00')
          for _ in 0..<owned_bytes_bench_messages_per_producer {
            if !worker_sender.send(payload) {
              panic()
            }
          }
        }),
      )
    }
    let received = try! owned_bytes_bench_receive_exact(
      receiver,
      4 * owned_bytes_bench_messages_per_producer,
    )
    for worker in workers {
      try! worker.join()
    }
    b.keep(received)
  })
}

///|
test "bench owned bytes steady 4p1c 64B" (b : @bench.T) {
  let (data_sender, data_receiver) = try! owned_bytes_bounded(1_024)
  let command_senders : Array[OwnedBytesSender] = []
  let workers : Array[@thread.Thread] = []
  for _ in 0..<4 {
    let (command_sender, command_receiver) = try! owned_bytes_bounded(1)
    command_senders.push(command_sender)
    workers.push(
      owned_bytes_bench_spawn_worker(command_receiver, data_sender.share()),
    )
  }

  for command_sender in command_senders {
    if !command_sender.send(b"warmup") {
      panic()
    }
  }
  ignore(
    owned_bytes_bench_receive_exact(
      data_receiver,
      4 * owned_bytes_bench_messages_per_producer,
    ),
  )

  b.bench(name="owned_bytes/steady/4p1c/64B", count=30, fn() {
    for command_sender in command_senders {
      if !(try! command_sender.send(b"run")) {
        panic()
      }
    }
    b.keep(
      try! owned_bytes_bench_receive_exact(
        data_receiver,
        4 * owned_bytes_bench_messages_per_producer,
      ),
    )
  })

  for command_sender in command_senders {
    command_sender.close()
  }
  for worker in workers {
    try! worker.join()
  }
}
