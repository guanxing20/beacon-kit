// SPDX-License-Identifier: BUSL-1.1
//
// Copyright (C) 2025, Berachain Foundation. All rights reserved.
// Use of this software is governed by the Business Source License included
// in the LICENSE file of this repository and at www.mariadb.com/bsl11.
//
// ANY USE OF THE LICENSED WORK IN VIOLATION OF THIS LICENSE WILL AUTOMATICALLY
// TERMINATE YOUR RIGHTS UNDER THIS LICENSE FOR THE CURRENT AND ALL OTHER
// VERSIONS OF THE LICENSED WORK.
//
// THIS LICENSE DOES NOT GRANT YOU ANY RIGHT IN ANY TRADEMARK OR LOGO OF
// LICENSOR OR ITS AFFILIATES (PROVIDED THAT YOU MAY USE A TRADEMARK OR LOGO OF
// LICENSOR AS EXPRESSLY REQUIRED BY THIS LICENSE).
//
// TO THE EXTENT PERMITTED BY APPLICABLE LAW, THE LICENSED WORK IS PROVIDED ON
// AN “AS IS” BASIS. LICENSOR HEREBY DISCLAIMS ALL WARRANTIES AND CONDITIONS,
// EXPRESS OR IMPLIED, INCLUDING (WITHOUT LIMITATION) WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, NON-INFRINGEMENT, AND
// TITLE.

package types

import (
	ctypes "github.com/berachain/beacon-kit/consensus-types/types"
	"github.com/berachain/beacon-kit/primitives/common"
	"github.com/berachain/beacon-kit/primitives/crypto"
)

// BlockProposerResponse is the response for the
// `/proof/block_proposer/{timestamp_id}` endpoint.
type BlockProposerResponse struct {
	// BeaconBlockHeader is the block header of which the hash tree root is the
	// beacon block root to verify against.
	BeaconBlockHeader *ctypes.BeaconBlockHeader `json:"beacon_block_header"`

	// BeaconBlockRoot is the beacon block root for this slot.
	BeaconBlockRoot common.Root `json:"beacon_block_root"`

	// ValidatorPubkey is the pubkey of the block proposer.
	ValidatorPubkey crypto.BLSPubkey `json:"validator_pubkey"`

	// ValidatorPubkeyProof can be verified against the beacon block root. Use
	// a Generalized Index of `z + (8 * ValidatorIndex)`, where z is the
	// Generalized Index of the 0 validator pubkey in the beacon block. In
	// the Deneb fork, z is 3254554418216960.
	ValidatorPubkeyProof []common.Root `json:"validator_pubkey_proof"`

	// ProposerIndexProof can be verified against the beacon block root. Use
	// a Generalized Index of 9 in the Deneb fork.
	ProposerIndexProof []common.Root `json:"proposer_index_proof"`
}

// ValidatorWithdrawalCredentialsResponse is the response for the
// `/proof/validator_withdrawal_credentials/{timestamp_id}/{validator_index}` endpoint.
type ValidatorWithdrawalCredentialsResponse struct {
	// BeaconBlockHeader is the block header of which the hash tree root is the
	// beacon block root to verify against.
	BeaconBlockHeader *ctypes.BeaconBlockHeader `json:"beacon_block_header"`

	// BeaconBlockRoot is the beacon block root for this slot.
	BeaconBlockRoot common.Root `json:"beacon_block_root"`

	// WithdrawalCredentials are the credentials of the requested validator.
	ValidatorWithdrawalCredentials ctypes.WithdrawalCredentials `json:"validator_withdrawal_credentials"`

	// WithdrawalCredentialsProof can be verified against the beacon block root.
	// Use a Generalized Index of `z + (8 * ValidatorIndex)`, where z is the
	// Generalized Index of the 0 validator withdrawal credentials in the beacon
	// block. In the Electra fork, z is 6350779162034177.
	WithdrawalCredentialsProof []common.Root `json:"withdrawal_credentials_proof"`
}
