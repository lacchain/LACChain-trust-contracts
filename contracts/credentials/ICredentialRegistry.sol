//SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

interface ICredentialRegistry {
    /**
     * Once revoked it will not longer be valid
     */
    function issue(bytes32 digest, uint256 exp, address identity) external;

    function revoke(bytes32 digest, address identity) external;

    /**
     * A digest can only be updated in the expiration time
     * If such digest is revoked it throws an exception
     * If such digest is not issued it throws an exception
     */
    function update(bytes32 digest, uint256 exp, address identity) external;

    function onHoldChange(
        bytes32 digest,
        address identity,
        bool onHoldStatus
    ) external;

    function getDetails(
        address issuer,
        bytes32 digest
    ) external view returns (uint256 iat, uint256 exp, bool onHold);

    /**
     * Just valid relative to the information contained in the contract
     * Validates "scenario 3" which means that data will be invalid when the expiration time has been reached by
     * the current timestamp; this means that the data has just expired because of the time has passed or because
     * the data has been revoked or because the data has been put on hold.
     */
    function isValidCredential(
        address issuer,
        bytes32 digest
    ) external view returns (bool);

    /**
     * Optional way to register a data change. In this case the delegate sends the data on behalf of the main actor
     *
     */
    function issueByDelegate(
        address identity,
        bytes32 digest,
        uint256 exp
    ) external;

    function revokeByDelegate(address identity, bytes32 digest) external;

    function onHoldByDelegate(
        address identity,
        bytes32 digest,
        bool onHoldStatus
    ) external;

    /**
     * @param delegateType: must coincide with some delegate that was registered under the "identity" by using the method "addDelegateType"
     * Optional way to register a data change. In this case the delegate sends the data on behalf of the main actor
     */
    function issueByDelegateWithCustomType(
        bytes32 delegateType,
        address identity,
        bytes32 digest,
        uint256 exp
    ) external;

    function revokeByDelegateWithCustomType(
        bytes32 delegateType,
        address identity,
        bytes32 digest
    ) external;

    function onHoldByDelegateWithCustomType(
        bytes32 delegateType,
        address identity,
        bytes32 digest,
        bool onHoldStatus
    ) external;

    function issueSigned(
        bytes32 digest,
        uint256 exp,
        address identity,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) external;

    function revokeSigned(
        bytes32 digest,
        address identity,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) external;

    function issueByDelegateSigned(
        address identity,
        bytes32 digest,
        uint256 exp,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) external;

    function revokeByDelegateSigned(
        address identity,
        bytes32 digest,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) external;

    function issueByDelegateWithCustomTypeSigned(
        bytes32 delegateType,
        address identity,
        bytes32 digest,
        uint256 exp,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) external;

    function revokeByDelegateWithCustomTypeSigned(
        bytes32 delegateType,
        address identity,
        bytes32 digest,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) external;

    event NewIssuance(
        bytes32 indexed digest,
        address indexed by,
        uint iat,
        uint exp
    );

    event NewUpdate(bytes32 indexed digest, address indexed by, uint exp);

    /**
     * Adding iat to the log allows verfying if the credential was actually issued onchan in the past(iat>0) or 
     just revoked (iat = 0)
     */
    event NewRevocation(
        bytes32 indexed digest,
        address indexed by,
        uint iat,
        uint exp
    );

    event NewOnHoldChange(
        bytes32 indexed digest,
        address indexed by,
        bool isOnHold,
        uint256 currentTime
    );

    /**
     * @param iat: date at which a data was issued
     * @param exp: date at which the data is expiring
     * @note:
     scenario 1: iat == 0, means a data was never issued via this registry; otherwise issued
     scenario 2: (iat > 0 && exp == 0) || (exp > current time) , means the data is still valid 
     scenario 3: exp < current time && exp !=0, means the data has expired (invalid)
     additionally:
     scenario 3.1: iat = 0 && scenario 3: means a data was never issued but revoked (invalid)
     */
    struct Detail {
        uint256 iat;
        uint256 exp;
        bool onHold;
    }
}