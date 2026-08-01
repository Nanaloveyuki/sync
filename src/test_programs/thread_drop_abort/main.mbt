///|
extern "C" fn native_thread_test_abort_if_unjoined() -> Unit = "sync_thread_test_abort_if_unjoined"

///|
fn main {
  ignore(@thread.current_thread_id())
  native_thread_test_abort_if_unjoined()
}
