///|
priv enum AtomicOperation {
  Load
  Store(Int)
  Swap(Int)
  FetchAdd(Int)
  CompareExchange(Int, Int)
} derive(Debug)

///|
impl @quickcheck.Arbitrary for AtomicOperation with fn arbitrary(size, rs) {
  let values = @quickcheck.int_range(-8, 9)
  match rs.next_uint() % 5U {
    0 => Load
    1 => Store(values.run(size, rs))
    2 => Swap(values.run(size, rs))
    3 => FetchAdd(values.run(size, rs))
    _ => CompareExchange(values.run(size, rs), values.run(size, rs))
  }
}

///|
impl @shrink.Shrink for AtomicOperation with fn shrink(operation) {
  match operation {
    Load => [||]
    Store(value) => @shrink.Shrink::shrink(value).map(value => Store(value))
    Swap(value) => @shrink.Shrink::shrink(value).map(value => Swap(value))
    FetchAdd(value) =>
      @shrink.Shrink::shrink(value).map(value => FetchAdd(value))
    CompareExchange(current, replacement) =>
      @shrink.Shrink::shrink((current, replacement)).map(pair => {
        let (current, replacement) = pair
        CompareExchange(current, replacement)
      })
  }
}

///|
test "atomic int operations follow a sequential model" {
  @quickcheck.check(
    (operations : Array[AtomicOperation]) => {
      let cell = AtomicInt::new(0)
      let mut expected = 0
      for operation in operations {
        let step_ok = match operation {
          Load => cell.load() == expected
          Store(new_value) => {
            cell.store(new_value)
            expected = new_value
            cell.load() == expected
          }
          Swap(new_value) => {
            let previous = cell.swap(new_value)
            let expected_previous = expected
            expected = new_value
            previous == expected_previous && cell.load() == expected
          }
          FetchAdd(delta) => {
            let previous = cell.fetch_add(delta)
            let expected_previous = expected
            expected += delta
            previous == expected_previous && cell.load() == expected
          }
          CompareExchange(current, replacement) => {
            let result = cell.compare_exchange(current, replacement)
            let exchanged = expected == current
            let expected_observed = expected
            if exchanged {
              expected = replacement
            }
            result.observed == expected_observed &&
            result.exchanged == exchanged &&
            cell.load() == expected
          }
        }
        guard step_ok else { return false }
      }
      true
    },
    count=200,
    max_size=64,
    max_shrinks=200,
    seed=20260825,
  )
}

///|
test "atomic bool swaps follow a sequential model" {
  @quickcheck.check(
    (values : Array[Bool]) => {
      let cell = AtomicBool::new(false)
      let mut expected = false
      for next_value in values {
        let previous = cell.swap(next_value)
        guard previous == expected else { return false }
        expected = next_value
        guard cell.load() == expected else { return false }
      }
      true
    },
    count=100,
    max_size=48,
    max_shrinks=100,
    seed=20260826,
  )
}
