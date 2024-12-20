#[test_only]
module account_protocol::metadata_tests;

// === Imports ===

use sui::{
    test_scenario::Self as ts,
};
use account_protocol::{
    metadata,
};

// === Constants ===

const OWNER: address = @0xCAFE;

// === Tests ===

#[test]
fun test_metadata_new() {
    let scenario = ts::begin(OWNER);

    let metadata = metadata::new(b"Name".to_string());
    assert!(metadata.get(b"name".to_string()) == b"Name".to_string());

    scenario.end();
}

#[test]
fun test_metadata_from_keys_values() {
    let scenario = ts::begin(OWNER);

    let keys = vector[
        b"name".to_string(),
        b"description".to_string(),
    ];
    let values = vector[
        b"Name".to_string(),
        b"Description".to_string(),
    ];

    let metadata = metadata::from_keys_values(keys, values);
    assert!(metadata.get(b"name".to_string()) == b"Name".to_string());
    assert!(metadata.get(b"description".to_string()) == b"Description".to_string());
    
    scenario.end();
}