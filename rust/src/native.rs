use std::{collections::{BTreeMap, HashMap}, fmt::Debug, io::Cursor, sync::{Arc, LazyLock, OnceLock, RwLock}, time::Duration};

use flexi_logger::{FileSpec, Logger, WriteMode};
use log::{error, info, warn};
use rustpush::{EntitlementAuthState, PushError, get_gateways_for_mccmnc};
use tokio::{runtime::{Handle, Runtime}, sync::Mutex};

use futures::FutureExt;
use crate::{RUNTIME, api::api::{PollResult, PushMessage, PushState, RegistrationPhase, approve_circle, decline_facetime, get_2fa_code, get_entitlements, get_phase, new_push_state, recv_wait, set_status, teardown_2fa}, frb_generated::FLUTTER_RUST_BRIDGE_HANDLER, init_logger};

#[derive(uniffi::Record)] 
pub struct FileInfo {
    pub duration: Option<f64>,
    pub width: u32,
    pub height: u32,
    pub thumbnail: Option<Vec<u8>>,
}

#[derive(uniffi::Enum)]
pub enum PackagedFile {
    Info(FileInfo),
    Failure(String),
}

#[uniffi::export(with_foreign)]
pub trait KotlinFilePackager: Send + Sync + Debug {
    fn get_file(&self, path: String) -> PackagedFile;
    fn scan_files(&self, paths: Vec<String>);
}

pub static PACKAGER_LOCK: OnceLock<Arc<dyn KotlinFilePackager>> = OnceLock::new();

#[uniffi::export(with_foreign)]
pub trait MsgReceiver: Send + Sync + Debug {
    fn receieved_msg(&self, msg: u64, retry: u64);
    fn native_ready(&self, is_ready: bool, state: Arc<NativePushState>);
    fn twofa_event(&self, success: bool);
}

#[uniffi::export(with_foreign)]
pub trait CarrierHandler: Send + Sync + Debug {
    fn got_gateway(&self, gateway: Option<String>, error: Option<String>);
}

#[derive(uniffi::Object)] 
pub struct NativePushState {
    state: Arc<PushState>
}

#[uniffi::export]
pub fn init_native(dir: String, handler: Arc<dyn MsgReceiver>, packager: Arc<dyn KotlinFilePackager>) {
    info!("rpljslf start");
    RUNTIME.spawn(async move {
        info!("rpljslf initting");

        let _ = PACKAGER_LOCK.set(packager);

        // TODO retry if this *unwrap* fails
        let state = Arc::new(NativePushState {
            state: new_push_state(dir).await
        });
        info!("rpljslf raed");
        handler.native_ready(state.get_ready().await, state.clone());
        info!("rpljslf dom");
    });
}

#[uniffi::export]
pub fn get_carrier(handler: Arc<dyn CarrierHandler>, mccmnc: String) {
    RUNTIME.spawn(async move {
        match get_gateways_for_mccmnc(&mccmnc).await {
            Ok(gateway) => handler.got_gateway(Some(gateway.gateway), None),
            Err(err) => handler.got_gateway(None, Some(err.to_string())),
        }
    });
}


#[uniffi::export(with_foreign)]
pub trait EntitlementHandler: Send + Sync + Debug {
    fn got_user(&self, gateway: Option<String>, error: Option<String>);
    fn perform_challenge(&self, challenge: String) -> Option<String>;
}

pub fn plist_to_buf<T: serde::Serialize>(value: &T) -> Result<Vec<u8>, plist::Error> {
    let mut buf: Vec<u8> = Vec::new();
    let writer = Cursor::new(&mut buf);
    plist::to_writer_xml(writer, &value)?;
    Ok(buf)
}

pub fn plist_to_string<T: serde::Serialize>(value: &T) -> Result<String, plist::Error> {
    plist_to_buf(value).map(|val| String::from_utf8(val).unwrap())
}


pub static QUEUED_MESSAGES: LazyLock<Mutex<(u64, HashMap<u64, PushMessage>)>> = LazyLock::new(|| Mutex::new((0, HashMap::new())));

#[uniffi::export]
impl NativePushState {

    pub fn start_loop(self: Arc<NativePushState>, handler: Arc<dyn MsgReceiver>) {
        RUNTIME.spawn(async move {
            loop {
                match std::panic::AssertUnwindSafe(recv_wait(&self.state)).catch_unwind().await {
                    Ok(yes) => {
                        match yes {
                            PollResult::Cont(Some(msg)) => {
                                if let PushMessage::TwoFaAuthEvent(event) = &msg {
                                    handler.twofa_event(*event);
                                    continue;
                                }

                                let mut locked_messages = QUEUED_MESSAGES.lock().await;
                                let key = locked_messages.0;
                                locked_messages.1.insert(key, msg);
                                locked_messages.0 = locked_messages.0.wrapping_add(1);
                                drop(locked_messages);

                                let handler_ref = handler.clone();
                                tokio::spawn(async move {
                                    let mut retry = 0;
                                    // sheesh, downloads take time...
                                    tokio::time::sleep(Duration::from_secs(30)).await;
                                    while QUEUED_MESSAGES.lock().await.1.contains_key(&key) {
                                        retry += 1;
                                        info!("re-emitting pointer {key}, retry {retry}");
                                        // we still haven't been handled, attempt to handle again
                                        handler_ref.receieved_msg(key, retry);
                                        tokio::time::sleep(Duration::from_secs(30)).await;
                                    }
                                });

                                info!("emitting pointer {key}");
                                handler.receieved_msg(key, 0);
                            },
                            PollResult::Cont(None) => continue,
                            PollResult::Stop => break
                        }
                    },
                    Err(payload) => {
                        let panic = match payload.downcast_ref::<&'static str>() {
                            Some(msg) => Some(*msg),
                            None => match payload.downcast_ref::<String>() {
                                Some(msg) => Some(msg.as_str()),
                                // Copy what rustc does in the default panic handler
                                None => None,
                            },
                        };
                        error!("Failed {:?}", panic);
                    }
                }
            }
            info!("finishing loop");
        });
    }

    pub fn get_entitlements(&self, handler: Arc<dyn EntitlementHandler>, mccmnc: String, subscriber: String, imei: String) {
        let state_ref = self.state.clone();
        RUNTIME.spawn(async move {
            let handler_copy = handler.clone();
            match get_entitlements(&state_ref, mccmnc, subscriber, imei, |challenge| async move {
                handler_copy.perform_challenge(challenge).ok_or(PushError::ICCAuthFailed)
            }).await {
                Ok(entitlements) => handler.got_user(Some(plist_to_string(&entitlements).unwrap()), None),
                Err(err) => handler.got_user(None, Some(err.to_string())),
            }
        });
    }

    pub fn get_state(self: Arc<NativePushState>) -> u64 {
        let arc_val = Arc::into_raw(self.state.clone()) as u64;
        info!("emitting state {arc_val}");
        arc_val
    }

    async fn get_ready(&self) -> bool {
        matches!(get_phase(&self.state).await, RegistrationPhase::Registered)
    }

    pub fn decline_facetime(&self, guid: String) {
        let state_ref = self.state.clone();
        RUNTIME.spawn(async move {
            if let Err(e) = decline_facetime(&state_ref, guid).await {
                warn!("Failed to decline facetime {e}");
            }
        });
    }

    pub fn teardown_2fa(&self, action: String, txnid: String) {
        let state_ref = self.state.clone();
        RUNTIME.spawn(async move {
            if let Err(e) = teardown_2fa(&state_ref, action, txnid).await {
                warn!("Failed to teardown 2fa {e}");
            }
        });
    }

    pub fn get_auth_code(&self, txnid: String) -> u32 {
        let state_ref = self.state.clone();
        RUNTIME.block_on(async move {
            match approve_circle(&state_ref, txnid).await {
                Ok(e) => e,
                Err(e) => {
                    warn!("Failed to get auth code {e}");
                    0
                }
            }
        })
    }
    
    pub fn publish_status(&self, guid: Option<String>) {
        let state_ref = self.state.clone();
        RUNTIME.spawn(async move {
            if let Err(e) = set_status(&state_ref, guid).await {
                warn!("Failed to decline publish status {e}");
            }
        });
    }
}