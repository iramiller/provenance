package cli

import (
	"fmt"
	"strings"

	"github.com/provenance-io/provenance/x/marker/types"

	"github.com/cosmos/cosmos-sdk/client"
	"github.com/cosmos/cosmos-sdk/client/flags"
	"github.com/cosmos/cosmos-sdk/client/tx"
	sdk "github.com/cosmos/cosmos-sdk/types"
	sdkErrors "github.com/cosmos/cosmos-sdk/types/errors"
	"github.com/cosmos/cosmos-sdk/version"

	"github.com/spf13/cobra"
)

const flagType = "type"

// NewTxCmd returns the top-level command for marker CLI transactions.
func NewTxCmd() *cobra.Command {
	txCmd := &cobra.Command{
		Use:                        types.ModuleName,
		Short:                      "Transaction commands for the marker module",
		DisableFlagParsing:         true,
		SuggestionsMinimumDistance: 2,
		RunE:                       client.ValidateCmd,
	}
	txCmd.AddCommand(
		GetCmdFinalize(),
		GetCmdActivate(),
		GetCmdCancel(),
		GetCmdDelete(),
		GetCmdMint(),
		GetCmdBurn(),
		GetCmdAddAccess(),
		GetCmdDeleteAccess(),
		GetCmdWithdrawCoins(),
		GetCmdAddMarker(),
	)
	return txCmd
}

// GetCmdAddMarker implements the create marker command
func GetCmdAddMarker() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "new [coin]",
		Args:  cobra.ExactArgs(1),
		Short: "Create a new marker",
		Long: strings.TrimSpace(
			fmt.Sprintf(`Creates a new marker in the Proposed state managed by the from address
with the given supply amount and denomination provided in the coin argument

Example:
$ %s tx marker new 1000hotdogcoin --type COIN --from mykey
`, version.AppName)),
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientTxContext(cmd)
			if err != nil {
				return err
			}
			markerType := ""
			coin, err := sdk.ParseCoinNormalized(args[0])
			if err != nil {
				return fmt.Errorf("invalid coin %s", args[0])
			}
			callerAddr := clientCtx.GetFromAddress()
			markerType, err = cmd.Flags().GetString(flagType)
			if err != nil {
				return fmt.Errorf("invalid marker type: %w", err)
			}
			typeValue := types.MarkerType_Coin
			if len(markerType) > 0 {
				typeValue = types.MarkerType(types.MarkerType_value["MARKER_TYPE_"+markerType])
				if typeValue < 1 {
					return fmt.Errorf("invalid marker type: %s; expected COIN|RESTRICTED", markerType)
				}
			}
			msg := types.NewAddMarkerRequest(coin.Denom, coin.Amount, callerAddr, callerAddr, typeValue)

			return tx.GenerateOrBroadcastTxCLI(clientCtx, cmd.Flags(), msg)
		},
	}
	cmd.Flags().String(flagType, "COIN", "a marker type to assign (default is COIN)")
	flags.AddTxFlagsToCmd(cmd)
	return cmd
}

// GetCmdMint implements the mint additional supply for marker command.
func GetCmdMint() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "mint [coin]",
		Args:  cobra.ExactArgs(1),
		Short: "Mint coins against the marker",
		Long: strings.TrimSpace(
			fmt.Sprintf(`Mints coins of the marker's denomination and places them
in the marker's account under escrow.  Caller must possess the mint permission and 
marker must be in the active status.

Example:
$ %s tx marker mint 1000hotdogcoin --from mykey
`, version.AppName)),
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientTxContext(cmd)
			if err != nil {
				return err
			}

			coin, err := sdk.ParseCoinNormalized(args[0])
			if err != nil {
				return sdkErrors.Wrapf(sdkErrors.ErrInvalidCoins, "invalid coin %s", args[0])
			}
			callerAddr := clientCtx.GetFromAddress()
			msg := types.NewMintRequest(callerAddr, coin)
			return tx.GenerateOrBroadcastTxCLI(clientCtx, cmd.Flags(), msg)
		},
	}
	flags.AddTxFlagsToCmd(cmd)
	return cmd
}

// GetCmdBurn implements the burn coin supply from marker command.
func GetCmdBurn() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "burn [coin]",
		Args:  cobra.ExactArgs(1),
		Short: "Burn coins from the marker",
		Long: strings.TrimSpace(
			fmt.Sprintf(`Burns the number of coins specified from the marker associated
with the coin's denomination.  Only coins held in the marker's account may be burned.  Caller
must possess the burn permission.  Use the bank send operation to transfer coin into the marker
for burning.  Marker must be in the active status to burn coin.

Example:
$ %s tx marker burn 1000hotdogcoin --from mykey
`, version.AppName)),
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientTxContext(cmd)
			if err != nil {
				return err
			}

			coin, err := sdk.ParseCoinNormalized(args[0])
			if err != nil {
				return sdkErrors.Wrapf(sdkErrors.ErrInvalidCoins, "invalid coin %s", args[0])
			}
			callerAddr := clientCtx.GetFromAddress()
			msg := types.NewBurnRequest(callerAddr, coin)
			return tx.GenerateOrBroadcastTxCLI(clientCtx, cmd.Flags(), msg)
		},
	}
	flags.AddTxFlagsToCmd(cmd)
	return cmd
}

// GetCmdFinalize implements the finalize marker command.
func GetCmdFinalize() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "finalize [denom]",
		Args:  cobra.ExactArgs(1),
		Short: "Finalize the marker account",
		Long: strings.TrimSpace(
			fmt.Sprintf(`Finalize a marker identified by the given denomination. Only
the marker manager may finalize a marker.  Once finalized callers who have been assigned
permission may perform mint,burn, or grant operations.  Only the manager may activate the marker.

Example:
$ %s tx marker finalize hotdogcoin --from mykey
`, version.AppName)),
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientTxContext(cmd)
			if err != nil {
				return err
			}

			callerAddr := clientCtx.GetFromAddress()
			msg := types.NewFinalizeRequest(args[0], callerAddr)
			return tx.GenerateOrBroadcastTxCLI(clientCtx, cmd.Flags(), msg)
		},
	}
	flags.AddTxFlagsToCmd(cmd)
	return cmd
}

// GetCmdActivate implements the activate marker command.
func GetCmdActivate() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "activate [denom]",
		Args:  cobra.ExactArgs(1),
		Short: "Activate the marker account",
		Long: strings.TrimSpace(
			fmt.Sprintf(`Activate a marker identified by the given denomination. Only
the marker manager may activate a marker.  Once activated any total supply less than the
amount in circulation will be minted.  Invariant checks will be enforced.

Example:
$ %s tx marker activate hotdogcoin --from mykey
`, version.AppName)),
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientTxContext(cmd)
			if err != nil {
				return err
			}

			callerAddr := clientCtx.GetFromAddress()
			msg := types.NewActivateRequest(args[0], callerAddr)
			return tx.GenerateOrBroadcastTxCLI(clientCtx, cmd.Flags(), msg)
		},
	}
	flags.AddTxFlagsToCmd(cmd)
	return cmd
}

// GetCmdCancel implements the cancel marker command.
func GetCmdCancel() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "cancel [denom]",
		Args:  cobra.ExactArgs(1),
		Short: "Cancel the marker account",
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientTxContext(cmd)
			if err != nil {
				return err
			}

			callerAddr := clientCtx.GetFromAddress()
			msg := types.NewCancelRequest(args[0], callerAddr)
			return tx.GenerateOrBroadcastTxCLI(clientCtx, cmd.Flags(), msg)
		},
	}
	flags.AddTxFlagsToCmd(cmd)
	return cmd
}

// GetCmdDelete implements the destroy marker command.
func GetCmdDelete() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "destroy [denom]",
		Args:  cobra.ExactArgs(1),
		Short: "Mark the marker for deletion",
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientTxContext(cmd)
			if err != nil {
				return err
			}

			callerAddr := clientCtx.GetFromAddress()
			msg := types.NewDeleteRequest(args[0], callerAddr)
			return tx.GenerateOrBroadcastTxCLI(clientCtx, cmd.Flags(), msg)
		},
	}
	flags.AddTxFlagsToCmd(cmd)
	return cmd
}

// GetCmdAddAccess implements the delegate access to a marker command.
func GetCmdAddAccess() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "grant [address] [denom] [permission]",
		Args:  cobra.ExactArgs(3),
		Short: "Grant access to a marker for the address coins from the marker",
		Long: strings.TrimSpace(
			fmt.Sprintf(`Grant administrative access to a marker.  From Address must have appropriate
existing access.  Permissions are appended to any existing access grant.  Valid permissions
are one of [mint, burn, deposit, withdraw, delete, grant].

Example:
$ %s tx marker grant pb1gghjut3ccd8ay0zduzj64hwre2fxs9ldmqhffj coindenom burn --from mykey
`, version.AppName)),
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientTxContext(cmd)
			if err != nil {
				return err
			}

			targetAddr, err := sdk.AccAddressFromBech32(args[0])
			if err != nil {
				return sdkErrors.Wrapf(err, "grant for invalid address %s", args[0])
			}
			grant := types.NewAccessGrant(targetAddr, types.AccessListByNames(args[2]))
			if err = grant.Validate(); err != nil {
				return sdkErrors.Wrapf(err, "invalid access grant permission: %s", args[2])
			}
			callerAddr := clientCtx.GetFromAddress()
			msg := types.NewAddAccessRequest(args[1], callerAddr, *grant)
			return tx.GenerateOrBroadcastTxCLI(clientCtx, cmd.Flags(), msg)
		},
	}
	flags.AddTxFlagsToCmd(cmd)
	return cmd
}

// GetCmdDeleteAccess implements the revoke administrative access for a marker command.
func GetCmdDeleteAccess() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "revoke [address] [denom]",
		Args:  cobra.ExactArgs(2),
		Short: "Revoke all access to a marker for the address",
		Long: strings.TrimSpace(
			fmt.Sprintf(`Revoke all administrative access to a marker for given access.
From Address must have appropriate existing access.

Example:
$ %s tx marker revoke pb1gghjut3ccd8ay0zduzj64hwre2fxs9ldmqhffj coindenom --from mykey
`, version.AppName)),
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientTxContext(cmd)
			if err != nil {
				return err
			}

			targetAddr, err := sdk.AccAddressFromBech32(args[0])
			if err != nil {
				return sdkErrors.Wrapf(err, "revoke grant for invalid address %s", args[0])
			}
			callerAddr := clientCtx.GetFromAddress()
			msg := types.NewDeleteAccessRequest(args[1], callerAddr, targetAddr)
			return tx.GenerateOrBroadcastTxCLI(clientCtx, cmd.Flags(), msg)
		},
	}
	flags.AddTxFlagsToCmd(cmd)
	return cmd
}

// GetCmdWithdrawCoins implements the withdraw coins from escrow command.
func GetCmdWithdrawCoins() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "withdraw [marker-denom] [coins] [(optional) recipient address]",
		Args:  cobra.RangeArgs(2, 3),
		Short: "Withdraw coins from the marker.",
		Long: "Withdraw coins from the marker escrow account.  Must be called by a user with the appropriate permissions. " +
			"If the recipient is not provided then the withdrawn amount is deposited in the caller's account.",
		RunE: func(cmd *cobra.Command, args []string) error {
			clientCtx, err := client.GetClientTxContext(cmd)
			if err != nil {
				return err
			}
			denom := args[0]
			coins, err := sdk.ParseCoinsNormalized(args[1])
			if err != nil {
				return sdkErrors.Wrapf(sdkErrors.ErrInvalidCoins, "invalid coin %s", args[0])
			}
			callerAddr := clientCtx.GetFromAddress()
			recipientAddr := sdk.AccAddress{}
			if len(args) == 3 {
				recipientAddr, err = sdk.AccAddressFromBech32(args[2])
				if err != nil {
					return sdkErrors.Wrapf(err, "invalid recipient address %s", args[0])
				}
			}
			msg := types.NewWithdrawRequest(callerAddr, recipientAddr, denom, coins)
			return tx.GenerateOrBroadcastTxCLI(clientCtx, cmd.Flags(), msg)
		},
	}
	flags.AddTxFlagsToCmd(cmd)
	return cmd
}
