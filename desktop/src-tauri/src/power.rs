//! Fixed, timed idle-system sleep protection. No display or forced-sleep assertion.
use std::{
    ffi::{c_char, c_void, CStr},
    io, ptr,
};

pub const LEASE_SECONDS: u64 = 15;

pub(crate) trait AssertionApi {
    type Handle;
    fn create(&self) -> io::Result<Self::Handle>;
    fn release(&self, handle: &Self::Handle) -> io::Result<()>;
}

pub(crate) struct Mac {
    seconds: f64,
}

pub(crate) struct Power<A: AssertionApi = Mac> {
    api: A,
    held: Option<A::Handle>,
    state: &'static str,
}

impl Power {
    pub fn new() -> Self {
        Self {
            api: Mac {
                seconds: LEASE_SECONDS as f64,
            },
            held: None,
            state: "released",
        }
    }
}

impl<A: AssertionApi> Power<A> {
    pub fn state(&self) -> &'static str {
        self.state
    }

    pub fn update(&mut self, requested: bool) {
        if let Some(handle) = &self.held {
            if self.api.release(handle).is_err() {
                self.state = "unavailable";
                return;
            }
            self.held = None;
        }
        self.state = if requested {
            match self.api.create() {
                Ok(handle) => {
                    self.held = Some(handle);
                    "held"
                }
                Err(_) => "unavailable",
            }
        } else {
            "released"
        };
    }
}

impl<A: AssertionApi> Drop for Power<A> {
    fn drop(&mut self) {
        if let Some(handle) = &self.held {
            let _ = self.api.release(handle);
        }
    }
}

struct Cf(*const c_void);
impl Drop for Cf {
    fn drop(&mut self) {
        unsafe { CFRelease(self.0) };
    }
}

fn string(value: &CStr) -> io::Result<Cf> {
    let value = unsafe { CFStringCreateWithCString(ptr::null(), value.as_ptr(), 0x08000100) };
    if value.is_null() {
        Err(io::Error::other("power unavailable"))
    } else {
        Ok(Cf(value))
    }
}

impl AssertionApi for Mac {
    type Handle = u32;

    fn create(&self) -> io::Result<u32> {
        let kind = string(c"PreventUserIdleSystemSleep")?;
        let name = string(c"Cuckoding active battle")?;
        let details = string(c"Bounded battle work; expires without a fresh shell heartbeat")?;
        let action = string(c"TimeoutActionTurnOff")?;
        let mut id = 0;
        // TurnOff retains our owned ID after expiry instead of permitting ID reuse.
        let code = unsafe {
            IOPMAssertionCreateWithDescription(
                kind.0,
                name.0,
                details.0,
                ptr::null(),
                ptr::null(),
                self.seconds,
                action.0,
                &mut id,
            )
        };
        if code == 0 && id != 0 {
            Ok(id)
        } else {
            Err(io::Error::other("power unavailable"))
        }
    }

    fn release(&self, handle: &u32) -> io::Result<()> {
        if unsafe { IOPMAssertionRelease(*handle) } == 0 {
            Ok(())
        } else {
            Err(io::Error::other("power release unavailable"))
        }
    }
}

#[link(name = "IOKit", kind = "framework")]
unsafe extern "C" {
    fn IOPMAssertionCreateWithDescription(
        kind: *const c_void,
        name: *const c_void,
        details: *const c_void,
        reason: *const c_void,
        bundle: *const c_void,
        timeout: f64,
        action: *const c_void,
        id: *mut u32,
    ) -> i32;
    fn IOPMAssertionRelease(id: u32) -> i32;
}

#[link(name = "CoreFoundation", kind = "framework")]
unsafe extern "C" {
    fn CFStringCreateWithCString(
        allocator: *const c_void,
        text: *const c_char,
        encoding: u32,
    ) -> *const c_void;
    fn CFRelease(value: *const c_void);
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        cell::RefCell,
        collections::BTreeSet,
        rc::Rc,
        thread,
        time::{Duration, Instant},
    };

    #[derive(Default)]
    struct Fake {
        next: u32,
        active: BTreeSet<u32>,
        fail_create: bool,
        fail_release: bool,
    }

    impl AssertionApi for Rc<RefCell<Fake>> {
        type Handle = u32;
        fn create(&self) -> io::Result<u32> {
            let mut state = self.borrow_mut();
            if state.fail_create {
                return Err(io::Error::other("fixture"));
            }
            state.next += 1;
            let id = state.next;
            state.active.insert(id);
            Ok(id)
        }
        fn release(&self, handle: &u32) -> io::Result<()> {
            let mut state = self.borrow_mut();
            if state.fail_release {
                return Err(io::Error::other("fixture"));
            }
            assert!(state.active.remove(handle));
            Ok(())
        }
    }

    fn fixture() -> (Power<Rc<RefCell<Fake>>>, Rc<RefCell<Fake>>) {
        let api = Rc::new(RefCell::new(Fake::default()));
        (
            Power {
                api: api.clone(),
                held: None,
                state: "released",
            },
            api,
        )
    }

    #[test]
    fn renew_releases_previous_and_idle_or_drop_releases_ownership() {
        let (mut power, api) = fixture();
        power.update(true);
        assert_eq!(power.state(), "held");
        power.update(true);
        assert_eq!(api.borrow().active, BTreeSet::from([2]));
        power.update(false);
        assert_eq!(power.state(), "released");
        assert!(api.borrow().active.is_empty());
        power.update(true);
        drop(power);
        assert!(api.borrow().active.is_empty());
    }

    #[test]
    fn failures_are_nonfatal_and_failed_release_never_accumulates_assertions() {
        let (mut power, api) = fixture();
        api.borrow_mut().fail_create = true;
        power.update(true);
        assert_eq!(power.state(), "unavailable");
        assert!(api.borrow().active.is_empty());
        api.borrow_mut().fail_create = false;
        power.update(true);
        api.borrow_mut().fail_release = true;
        power.update(true);
        power.update(false);
        assert_eq!(power.state(), "unavailable");
        assert_eq!(api.borrow().next, 1);
        assert_eq!(api.borrow().active, BTreeSet::from([1]));
        api.borrow_mut().fail_release = false;
        drop(power);
        assert!(api.borrow().active.is_empty());
    }

    #[link(name = "IOKit", kind = "framework")]
    unsafe extern "C" {
        fn IOPMAssertionCopyProperties(id: u32) -> *const c_void;
        fn IOPMCopyAssertionsByProcess(result: *mut *const c_void) -> i32;
    }
    #[link(name = "CoreFoundation", kind = "framework")]
    unsafe extern "C" {
        fn CFDictionaryGetValue(dictionary: *const c_void, key: *const c_void) -> *const c_void;
        fn CFNumberGetValue(value: *const c_void, kind: isize, output: *mut i64) -> u8;
        fn CFGetTypeID(value: *const c_void) -> usize;
        fn CFNumberGetTypeID() -> usize;
        fn CFNumberCreate(
            allocator: *const c_void,
            kind: isize,
            value: *const i64,
        ) -> *const c_void;
        fn CFArrayGetCount(array: *const c_void) -> isize;
        fn CFArrayGetValueAtIndex(array: *const c_void, index: isize) -> *const c_void;
    }

    fn level(id: u32) -> Option<i64> {
        let properties = unsafe { IOPMAssertionCopyProperties(id) };
        if properties.is_null() {
            return None;
        }
        let properties = Cf(properties);
        let key = string(c"AssertLevel").unwrap();
        let value = unsafe { CFDictionaryGetValue(properties.0, key.0) };
        if value.is_null() || unsafe { CFGetTypeID(value) != CFNumberGetTypeID() } {
            return None;
        }
        let mut output = 0_i64;
        (unsafe { CFNumberGetValue(value, 4, &mut output) } != 0).then_some(output)
    }

    fn active(id: u32) -> bool {
        let mut processes = ptr::null();
        assert_eq!(unsafe { IOPMCopyAssertionsByProcess(&mut processes) }, 0);
        assert!(!processes.is_null());
        let processes = Cf(processes);
        let pid = i64::from(std::process::id());
        let key = Cf(unsafe { CFNumberCreate(ptr::null(), 4, &pid) });
        assert!(!key.0.is_null());
        // Inspect only our PID/ID; never log unrelated processes or assertion details.
        let assertions = unsafe { CFDictionaryGetValue(processes.0, key.0) };
        if assertions.is_null() {
            return false;
        }
        let key = string(c"AssertionId").unwrap();
        (0..unsafe { CFArrayGetCount(assertions) }).any(|index| {
            let assertion = unsafe { CFArrayGetValueAtIndex(assertions, index) };
            let value = unsafe { CFDictionaryGetValue(assertion, key.0) };
            let mut output = 0_i64;
            !value.is_null()
                && unsafe {
                    CFGetTypeID(value) == CFNumberGetTypeID()
                        && CFNumberGetValue(value, 4, &mut output) != 0
                }
                && output == i64::from(id)
        })
    }

    #[test]
    fn native_assertion_turns_off_without_renewal_then_releases_its_owned_id() {
        // Only this process's assertion is inspected; this test never asks the Mac to sleep.
        let mut power = Power {
            api: Mac { seconds: 1.0 },
            held: None,
            state: "released",
        };
        power.update(true);
        assert_eq!(power.state(), "held");
        let id = power.held.unwrap();
        assert_eq!(level(id), Some(255));
        assert!(active(id));
        let deadline = Instant::now() + Duration::from_secs(5);
        while active(id) && Instant::now() < deadline {
            thread::sleep(Duration::from_millis(50));
        }
        // TurnOff retains the ID: an expired lease cannot make us release a reused ID.
        assert!(!active(id));
        assert!(level(id).is_some());
        power.update(false);
        assert_eq!(power.state(), "released");
        assert_eq!(level(id), None);
        power.update(true);
        let id = power.held.unwrap();
        drop(power);
        assert_eq!(level(id), None);
    }
}
