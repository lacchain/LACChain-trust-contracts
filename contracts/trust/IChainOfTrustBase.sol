//SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

interface IChainOfTrustBase {
    struct groupDetail {
        uint256 gId;
        string did;
    }

    struct MemberProfile {
        uint256 iat;
        uint256 exp;
        uint256 gId;
        address trustedBy;
        string did;
        bool isValid;
    }

    struct MemberDetail {
        uint256 iat;
        uint256 exp;
    }
    /**
     * @dev Emmited event when an entity changes the did it claims to be associated with.
     * Note: Relating did and entity must be made by resolving the correspondent did document.
     *  The verification relationship must be resolved by querying the PKD contract
     *  (a contract component in the Chain Of Trust Stack of contracts)
     */
    event DidChanged(address entity, string did, uint256 prevBlock);
    /**
     * @dev Emmited when the maximum depth is updated.
     * Note: Due to gas consumption constraints, the maximum depth shouldn't be bigger than 5.
     */
    event DepthChanged(uint8 prevDepth, uint8 depth, uint256 prevBlock);
    /**
     * @dev Emmited event when Revoke mode is updated. There are three modes:
     * - REVOKEMODE=1: A parent entity can revoke a child entity it added AND a Root Entity can also revoke any child entity
     * - REVOKEMODE=2: Any parent (including the root entity) can revoke any child entity, only if the parent
     *   entity is an ancestor of the child entity.
     */
    event RevokeModeChanged(
        uint8 prevRevokeMode,
        uint8 revokeMode,
        uint256 prevBlock
    );
    /**
     * @dev Emmited event when contract resposibilities are changed.
     * - isRootMaintainer=True: Means the root entity is also able to modify maxDepth and RevokeMode params.
     * - isRootMaintainer=False: Means that only the owner of the contract is able to modify maxDepth and RevokeMode params
     */
    event MaintainerModeChanged(bool isRootMaintainer, uint256 prevBlock);
    /**
     * @dev Emmited the when a participant is added to a "Group" of trusted entities orchestrated by a common "parent Entity"
     */
    event GroupMemberChanged(
        address indexed parentEntity,
        address indexed memberEntity,
        string did,
        uint256 iat,
        uint256 exp,
        uint256 prevBlock
    );
    /**
     * @dev Emmited the when a participant is removed from a "Group" of trusted entities orchestrated by a common "parent Entity"
     */
    event GroupMemberRevoked(
        address indexed revokerEntity,
        address indexed parentEntity,
        address indexed memberEntity,
        string did,
        uint256 exp,
        uint256 prevBlock
    );

    /**
     * @dev Emmited the when the root manager is updated to a new one.
     * @param executor: The account that executed the update
     * @param rootManager: The current root manager
     * @param newRootManager: The new root manager
     */
    event RootManagerUpdated(
        address indexed executor,
        address indexed rootManager,
        address indexed newRootManager
    );

    /**
     * @dev Only current root manager or contract owner can transfer root manager
     * @param newRootManager: The account to be the new root manager
     * @param did: The did in which the root manager is associated to in some kind of relationship.
     * The chosen relationship is up to the application layer.
     */
    function transferRoot(address newRootManager, string memory did) external;

    function updateMaintainerMode(bool rootMaintainer) external;

    function updateDepth(uint8 chainDepth) external;

    function updateRevokeMode(uint8 revokeMode) external;

    function updateDid(string memory did) external;

    function addOrUpdateGroupMember(
        address memberEntity,
        string memory did,
        uint256 period
    ) external;

    function revokeMember(address memberEntity, string memory did) external;

    function revokeMemberByRoot(
        address memberEntity,
        string memory did
    ) external;

    function revokeMemberByAnyAncestor(
        address memberEntity,
        string memory did
    ) external;

    function getMemberDetailsByEntityManager(
        address memberEntityManager
    ) external view returns (MemberProfile memory member);

    /**
     * @dev On emitted indicates the previous block number at which some change occurred on this smart contract
     * @param contractPrevBlock The immediately previous block number at which at least one change occurred
     */
    event ContractChange(uint256 contractPrevBlock);
}
