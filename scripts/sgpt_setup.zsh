#!/bin/zsh
# SGPT_SETUP_SCRIPT_VERSION_7
# Zsh is specified, but we'll try to make it somewhat portable or guide for Bash users.

# Script to interactively configure SGPT environment and config file

# --- Configuration ---
SGPT_CONFIG_FILE_DIR="$HOME/.config/shell_gpt"
SGPT_CONFIG_FILE="$SGPT_CONFIG_FILE_DIR/.sgptrc" # Common path
GCLOUD_SDK_PARENT_DIR="$HOME/google-cloud-sdk" # Parent directory for GCloud SDK
GCLOUD_SDK_ACTUAL_INSTALL_PATH="$GCLOUD_SDK_PARENT_DIR/google-cloud-sdk" # Actual path created by Google's installer
SCRIPT_MARKER="# Added by sgpt_setup.zsh"

# --- OS and Shell Detection ---
OS_TYPE=$(uname -s)
CURRENT_SHELL_NAME=$(basename "$SHELL")
PREFERRED_SHELL_CONFIG_FILE=""
GCLOUD_SDK_INSTALL_URL="https://cloud.google.com/sdk/docs/install"

# --- Helper Functions (with prepended type for clarity) ---
print_info() { print -P "%F{cyan}INFO:%f $1"; }
print_success() { print -P "%F{green}SUCCESS:%f $1"; }
print_warning() { print -P "%F{yellow}WARNING:%f $1"; }
print_error() { print -P "%F{red}ERROR:%f $1"; }

print_info "Script started (v7). OS: $OS_TYPE, Shell: $CURRENT_SHELL_NAME"
print_info "Attempting to determine preferred shell config file..."
if [[ "$OS_TYPE" == "Darwin" ]]; then
    if [[ "$CURRENT_SHELL_NAME" == "zsh" ]]; then
        PREFERRED_SHELL_CONFIG_FILE="$HOME/.zshrc"
    elif [[ "$CURRENT_SHELL_NAME" == "bash" ]]; then
        if [[ -f "$HOME/.bash_profile" ]]; then
            PREFERRED_SHELL_CONFIG_FILE="$HOME/.bash_profile"
        elif [[ -f "$HOME/.bashrc" ]]; then
            PREFERRED_SHELL_CONFIG_FILE="$HOME/.bashrc"
        else 
            PREFERRED_SHELL_CONFIG_FILE="$HOME/.bash_profile"
        fi
    else
        PREFERRED_SHELL_CONFIG_FILE="$HOME/.${CURRENT_SHELL_NAME}rc" 
    fi
elif [[ "$OS_TYPE" == "Linux" ]]; then
    if [[ "$CURRENT_SHELL_NAME" == "zsh" ]]; then
        PREFERRED_SHELL_CONFIG_FILE="$HOME/.zshrc"
    elif [[ "$CURRENT_SHELL_NAME" == "bash" ]]; then
        PREFERRED_SHELL_CONFIG_FILE="$HOME/.bashrc"
    else
        PREFERRED_SHELL_CONFIG_FILE="$HOME/.${CURRENT_SHELL_NAME}rc" 
    fi
else
    print_warning "Unsupported OS type: $OS_TYPE. Some features may not work as expected."
    PREFERRED_SHELL_CONFIG_FILE="$HOME/.profile" 
fi
if [[ -n "$PREFERRED_SHELL_CONFIG_FILE" ]]; then
    print_info "Preferred shell config file for exports: $PREFERRED_SHELL_CONFIG_FILE"
else
    print_warning "Could not determine a preferred shell config file. PATH/env exports will need manual setup."
fi

ask_yes_no() {
    local prompt_text="$1" 
    local default_answer="${2:-n}"
    local answer

    while true; do
        if [[ "$default_answer" == "y" ]]; then
            read -r "answer?${prompt_text} [Y/n]: "
            answer="${answer:-y}"
        else
            read -r "answer?${prompt_text} [y/N]: "
            answer="${answer:-n}"
        fi

        case "$answer" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) print_warning "Please answer yes (y) or no (n).";;
        esac
    done
}

check_gcloud_in_path() {
    print_info "Checking for 'gcloud' command in PATH..."
    if command -v gcloud &>/dev/null; then
        print_success "'gcloud' command found in PATH."
        return 0
    else
        print_warning "'gcloud' command NOT found in PATH."
        return 1
    fi
}

get_sgptrc_value() {
    local key_to_find="$1"
    local value=""
    if [[ -f "$SGPT_CONFIG_FILE" ]]; then
        # Grep for the line starting with the key (ignoring leading whitespace), ensure it's not commented out.
        # Then extract value after '=', and strip leading/trailing whitespace and quotes.
        local line_content
        line_content=$(grep -E "^\s*${key_to_find}\s*=" "$SGPT_CONFIG_FILE" | grep -v "^\s*#" | head -n 1)
        if [[ -n "$line_content" ]]; then
            # Using echo and sed for stripping.
            value=$(echo "$line_content" | cut -d'=' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')
        fi
    fi
    echo "$value"
}

update_sgptrc_value() {
    local key="$1"
    local value="$2"
    local temp_file
    temp_file=$(mktemp)
    local found=false
    print_info "Updating .sgptrc: Setting '$key'..."

    if [[ -f "$SGPT_CONFIG_FILE" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            # Match if the line starts with the key (ignoring leading whitespace), optionally followed by spaces/tabs, then '='
            # This regex is a bit more robust for matching the key itself.
            if [[ "$line" =~ ^\s*${key}\s*= ]]; then
                print "${key}=${value}" >> "$temp_file"
                found=true
            else
                print "$line" >> "$temp_file"
            fi
        done < "$SGPT_CONFIG_FILE"
    fi

    if ! "$found"; then
        print "${key}=${value}" >> "$temp_file"
    fi
    mv "$temp_file" "$SGPT_CONFIG_FILE"
    print_info ".sgptrc update for '$key' complete."
}

add_export_to_shell_config() {
    local export_line_to_add="$1"
    local variable_name="$2" 

    if [[ -z "$PREFERRED_SHELL_CONFIG_FILE" ]]; then
        print_warning "No preferred shell config file determined. Cannot add export for $variable_name automatically."
        print_warning "Please add the following line to your shell config manually:"
        print_warning "  $export_line_to_add"
        return 1
    fi

    print_info "Checking $PREFERRED_SHELL_CONFIG_FILE for existing '$variable_name' export by this script..."
    if [[ -f "$PREFERRED_SHELL_CONFIG_FILE" ]] && grep -qF "$SCRIPT_MARKER" "$PREFERRED_SHELL_CONFIG_FILE" && grep -qF "$variable_name" "$PREFERRED_SHELL_CONFIG_FILE"; then
        if grep -qFx "$export_line_to_add" "$PREFERRED_SHELL_CONFIG_FILE"; then
            print_info "Exact export line for '$variable_name' already exists in $PREFERRED_SHELL_CONFIG_FILE."
            return 0
        else
            print_warning "A different export for '$variable_name' by this script might exist. Adding the new one."
        fi
    fi
    
    local add_action_prompt="Add export for '$variable_name' to $PREFERRED_SHELL_CONFIG_FILE?"
    if [[ ! -f "$PREFERRED_SHELL_CONFIG_FILE" ]]; then
        add_action_prompt="$PREFERRED_SHELL_CONFIG_FILE does not exist. Create it and add export for '$variable_name'?"
    fi

    if ask_yes_no "$add_action_prompt"; then
        print_info "Adding export for '$variable_name' to $PREFERRED_SHELL_CONFIG_FILE..."
        if [[ ! -f "$PREFERRED_SHELL_CONFIG_FILE" ]]; then
            print "# Created by sgpt_setup.zsh $SCRIPT_MARKER" > "$PREFERRED_SHELL_CONFIG_FILE"
        fi
        if [[ -s "$PREFERRED_SHELL_CONFIG_FILE" ]] && [[ "$(tail -c1 "$PREFERRED_SHELL_CONFIG_FILE"; echo x)" != $'\nx' ]]; then
            print "" >> "$PREFERRED_SHELL_CONFIG_FILE"
        fi
        print "\n# Configuration for $variable_name $SCRIPT_MARKER" >> "$PREFERRED_SHELL_CONFIG_FILE"
        print "$export_line_to_add" >> "$PREFERRED_SHELL_CONFIG_FILE"
        print_success "Export for '$variable_name' added to $PREFERRED_SHELL_CONFIG_FILE."
        print_warning "Please run 'source $PREFERRED_SHELL_CONFIG_FILE' or open a new terminal session for changes to take effect."
    else
        print_warning "Skipped adding export for '$variable_name' to $PREFERRED_SHELL_CONFIG_FILE."
        print_warning "You may need to set it manually: $export_line_to_add"
    fi
}

# --- gcloud Checks and Installation ---
GCLOUD_INSTALLED_IN_PATH=false
GCLOUD_DIR_EXISTS_BUT_NOT_IN_PATH=false
PATH_EXPORT_LINE_GCLOUD="" 

if check_gcloud_in_path; then
    GCLOUD_INSTALLED_IN_PATH=true
    if ask_yes_no "gcloud is installed and in PATH. Would you like to check for updates to gcloud components now?"; then
        if gcloud components update; then
            print_success "gcloud components updated successfully (or are already up-to-date)."
        else
            print_warning "gcloud components update encountered an issue or was skipped by user."
        fi
    fi
else
    print_info "Checking for gcloud SDK directory at $GCLOUD_SDK_ACTUAL_INSTALL_PATH..."
    if [[ -d "$GCLOUD_SDK_ACTUAL_INSTALL_PATH" ]]; then
        GCLOUD_DIR_EXISTS_BUT_NOT_IN_PATH=true
        print_error "The gcloud SDK installation directory '$GCLOUD_SDK_ACTUAL_INSTALL_PATH' exists, but 'gcloud' is not in your PATH."
        print_warning "This script will NOT attempt to reinstall over an existing directory."
        
        GCLOUD_SDK_BIN_PATH_FOR_EXPORT="$GCLOUD_SDK_ACTUAL_INSTALL_PATH/bin"
        PATH_EXPORT_LINE_GCLOUD="export PATH=\"$GCLOUD_SDK_BIN_PATH_FOR_EXPORT:\$PATH\" $SCRIPT_MARKER"
        print_warning "Offering to add existing gcloud SDK to PATH..."
        add_export_to_shell_config "$PATH_EXPORT_LINE_GCLOUD" "PATH_gcloud_existing"

        print_error "\nACTION REQUIRED: The gcloud SDK path may have been added/updated in '$PREFERRED_SHELL_CONFIG_FILE'."
        print_error "You MUST now source this file in your CURRENT terminal by running:"
        print_error "  source $PREFERRED_SHELL_CONFIG_FILE"
        print_error "After sourcing, please RE-RUN THIS SCRIPT ($0) to continue."
        print_warning "If issues persist, or if this is an old/broken install, consider removing the directory:"
        print_warning "  rm -rf \"$GCLOUD_SDK_ACTUAL_INSTALL_PATH\""
        print_warning "and then re-run this script to attempt a fresh headless installation."
        exit 1 
    elif command -v curl &>/dev/null; then 
        if ask_yes_no "Attempt to install gcloud SDK headlessly using Google's official script? (Installs to $GCLOUD_SDK_PARENT_DIR)"; then
            print_info "Attempting headless installation of Google Cloud SDK to $GCLOUD_SDK_PARENT_DIR..."
            print_info "This may take a few minutes. Please be patient."
            mkdir -p "$GCLOUD_SDK_PARENT_DIR" 
            
            local install_log_temp
            install_log_temp=$(mktemp)
            if curl -sSL https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir="$GCLOUD_SDK_PARENT_DIR" > "$install_log_temp" 2>&1; then
                cat "$install_log_temp" 
                rm "$install_log_temp"
                print_success "Google Cloud SDK installation script finished."
                print_warning "IMPORTANT: The gcloud SDK has been installed into '$GCLOUD_SDK_ACTUAL_INSTALL_PATH'."
                
                GCLOUD_SDK_BIN_PATH_FOR_EXPORT="$GCLOUD_SDK_ACTUAL_INSTALL_PATH/bin"
                PATH_EXPORT_LINE_GCLOUD="export PATH=\"$GCLOUD_SDK_BIN_PATH_FOR_EXPORT:\$PATH\" $SCRIPT_MARKER"
                add_export_to_shell_config "$PATH_EXPORT_LINE_GCLOUD" "PATH_gcloud_new_install"

                print_error "\nACTION REQUIRED: The gcloud SDK path may have been added/updated in '$PREFERRED_SHELL_CONFIG_FILE'."
                print_error "You MUST now source this file in your CURRENT terminal by running:"
                print_error "  source $PREFERRED_SHELL_CONFIG_FILE"
                print_error "After sourcing, please RE-RUN THIS SCRIPT ($0) to continue with Vertex AI configuration."
                exit 1 
            else
                print_error "Google Cloud SDK headless installation FAILED. Google's script exited with an error."
                print_error "Output from Google's install script:"
                cat "$install_log_temp"
                rm "$install_log_temp"
                print_info "Please try manual installation by visiting: $GCLOUD_SDK_INSTALL_URL"
            fi
        else
            print_info "Skipping automatic gcloud installation attempt."
            print_info "For manual installation, please visit: $GCLOUD_SDK_INSTALL_URL"
        fi
    else 
        print_error "'curl' command not found. 'curl' is required for the headless gcloud installation attempt."
        print_info "Please install 'curl' first, or install gcloud manually by visiting: $GCLOUD_SDK_INSTALL_URL"
    fi
fi

# --- Main Configuration Menu ---
print_info "\n--- SGPT Interactive Configuration ---"
print_info "SGPT config file will be: $SGPT_CONFIG_FILE"
print_info "--------------------------------------------------------------------"

mkdir -p "$SGPT_CONFIG_FILE_DIR"
if [[ -f "$SGPT_CONFIG_FILE" ]]; then
    BACKUP_FILE="${SGPT_CONFIG_FILE}.bak_$(date +%Y%m%d_%H%M%S)"
    cp "$SGPT_CONFIG_FILE" "$BACKUP_FILE"
    print_info "Backed up existing $SGPT_CONFIG_FILE to $BACKUP_FILE"
else
    touch "$SGPT_CONFIG_FILE" # Ensure file exists for get_sgptrc_value
    print_info "Created empty config file: $SGPT_CONFIG_FILE"
fi

options_texts[1]="Configure OpenAI API Key"
options_texts[2]="Configure Google AI Studio API Key (for Gemini)"
options_texts[3]="Configure Google Vertex AI (ADC - Application Default Credentials)"
options_texts[4]="Exit"

main_menu_loop_active=true
while "$main_menu_loop_active"; do
    print_info "\nWhich API backend do you want to configure SGPT for?"
    idx=1
    while [[ $idx -le ${#options_texts[@]} ]]; do
        print_info "$idx) ${options_texts[$idx]}"
        ((idx++))
    done

    user_choice_num=""
    read -r "user_choice_num?Please choose an option (1-${#options_texts[@]}): "
    
    if ! [[ "$user_choice_num" =~ ^[0-9]+$ ]] || ! [[ "$user_choice_num" -ge 1 && "$user_choice_num" -le ${#options_texts[@]} ]]; then
        print_warning "Invalid selection. Please enter a number between 1 and ${#options_texts[@]}."
        continue 
    fi

    print_info "You selected option $user_choice_num: ${options_texts[$user_choice_num]}"

    case "$user_choice_num" in
        1) # OpenAI
            print_info "\nConfiguring for OpenAI..."
            current_api_key=$(get_sgptrc_value "OPENAI_API_KEY")
            read -r "api_key_val_openai?Enter your OpenAI API Key (sk-...) [$current_api_key]: "
            api_key_val_openai="${api_key_val_openai:-$current_api_key}"
            if [[ -z "$api_key_val_openai" ]] || [[ "$api_key_val_openai" == DISABLED_SGPT_SETUP* ]]; then # Check for placeholder too
                print_error "API Key cannot be empty or a placeholder."
                continue 
            fi

            current_model=$(get_sgptrc_value "DEFAULT_MODEL")
            script_default_model="gpt-4o-mini"
            prompt_default_model="${current_model:-$script_default_model}"
            read -r "default_model_val_openai?Enter default OpenAI model (e.g., gpt-4o-mini) [$prompt_default_model]: "
            DEFAULT_MODEL_OPENAI="${default_model_val_openai:-$prompt_default_model}"

            update_sgptrc_value "OPENAI_API_KEY" "\"$api_key_val_openai\""
            update_sgptrc_value "GOOGLE_API_KEY" "\"DISABLED_SGPT_SETUP_USING_OPENAI\""
            update_sgptrc_value "GOOGLE_CLOUD_PROJECT" "\"\"" 
            update_sgptrc_value "VERTEXAI_LOCATION" "\"\"" 
            update_sgptrc_value "DEFAULT_MODEL" "$DEFAULT_MODEL_OPENAI"
            update_sgptrc_value "USE_LITELLM" "true" 

            print_success "\nSGPT config file ($SGPT_CONFIG_FILE) updated for OpenAI."
            
            OPENAI_EXPORT_LINE="export OPENAI_API_KEY=\"$api_key_val_openai\" $SCRIPT_MARKER"
            add_export_to_shell_config "$OPENAI_EXPORT_LINE" "OPENAI_API_KEY"
            main_menu_loop_active=false 
            ;;
        2) # Google AI Studio
            print_info "\nConfiguring for Google AI Studio (Gemini API Key)..."
            current_api_key=$(get_sgptrc_value "GOOGLE_API_KEY")
            read -r "api_key_val_google?Enter your Google AI Studio API Key (AIzaSy...) [$current_api_key]: "
            api_key_val_google="${api_key_val_google:-$current_api_key}"
            if [[ -z "$api_key_val_google" ]] || [[ "$api_key_val_google" == DISABLED_SGPT_SETUP* ]]; then
                print_error "API Key cannot be empty or a placeholder."
                continue 
            fi

            current_model=$(get_sgptrc_value "DEFAULT_MODEL")
            script_default_model="gemini/gemini-1.5-pro-latest"
            prompt_default_model="${current_model:-$script_default_model}"
            read -r "default_model_val_google?Enter default Gemini model (e.g., gemini/gemini-1.5-pro-latest) [$prompt_default_model]: "
            DEFAULT_MODEL_GEMINI="${default_model_val_google:-$prompt_default_model}"

            update_sgptrc_value "GOOGLE_API_KEY" "\"$api_key_val_google\""
            update_sgptrc_value "OPENAI_API_KEY" "\"DISABLED_SGPT_SETUP_USING_GOOGLE_AI_STUDIO\""
            update_sgptrc_value "GOOGLE_CLOUD_PROJECT" "\"\"" 
            update_sgptrc_value "VERTEXAI_LOCATION" "\"\"" 
            update_sgptrc_value "DEFAULT_MODEL" "$DEFAULT_MODEL_GEMINI"
            update_sgptrc_value "USE_LITELLM" "true" 

            print_success "\nSGPT config file ($SGPT_CONFIG_FILE) updated for Google AI Studio."

            GOOGLE_EXPORT_LINE="export GOOGLE_API_KEY=\"$api_key_val_google\" $SCRIPT_MARKER"
            add_export_to_shell_config "$GOOGLE_EXPORT_LINE" "GOOGLE_API_KEY"
            main_menu_loop_active=false 
            ;;
        3) # Vertex AI (ADC)
            if ! check_gcloud_in_path; then 
                GCLOUD_INSTALLED_IN_PATH=false 
            else
                GCLOUD_INSTALLED_IN_PATH=true
            fi

            if ! "$GCLOUD_INSTALLED_IN_PATH"; then
                print_error "Vertex AI setup requires Google Cloud SDK ('gcloud') to be installed and in your PATH."
                if "$GCLOUD_DIR_EXISTS_BUT_NOT_IN_PATH"; then 
                     print_error "The SDK directory '$GCLOUD_SDK_ACTUAL_INSTALL_PATH' was found, but 'gcloud' is not in PATH."
                     print_error "Please add '$GCLOUD_SDK_ACTUAL_INSTALL_PATH/bin' to your PATH in '$PREFERRED_SHELL_CONFIG_FILE',"
                     print_error "source it (e.g., 'source $PREFERRED_SHELL_CONFIG_FILE'), and then re-run this script."
                else
                    print_error "This script can attempt a headless install if 'curl' is available and the SDK directory is not present."
                    print_error "Please re-run the script. If offered, accept the headless install, then source your shell config and run again."
                fi
                continue 
            fi

            print_info "\nConfiguring for Google Vertex AI (Application Default Credentials)..."

            current_gcp_project=$(get_sgptrc_value "GOOGLE_CLOUD_PROJECT")
            # Also try to get from gcloud config as a fallback default if not in .sgptrc
            gcloud_config_project=$(gcloud config get-value core/project 2>/dev/null)
            prompt_default_gcp_project="${current_gcp_project:-$gcloud_config_project}"
            print_info "The gcloud command requires the ALPHANUMERIC Project ID (e.g., 'my-cool-project-123'), not the Project Number."
            read -r "project_id_val_vertex?Enter your Google Cloud Project ID (alphanumeric) [$prompt_default_gcp_project]: "
            GOOGLE_CLOUD_PROJECT_TO_SET="${project_id_val_vertex:-$prompt_default_gcp_project}"

            if [[ -z "$GOOGLE_CLOUD_PROJECT_TO_SET" ]]; then
                print_error "Google Cloud Project ID is required for Vertex AI setup. Aborting this option."
                continue 
            fi

            print_warning "\nFor Vertex AI ADC to work correctly with user credentials, ensure you have ALREADY run:"
            print_warning "1. gcloud auth application-default login --project=$GOOGLE_CLOUD_PROJECT_TO_SET"
            print_warning "2. gcloud auth application-default set-quota-project $GOOGLE_CLOUD_PROJECT_TO_SET"
            print_info "(This script cannot run these for you as they may require browser interaction or specific permissions)."
            if ! ask_yes_no "Confirm you have ALREADY performed these two 'gcloud auth' steps for project '$GOOGLE_CLOUD_PROJECT_TO_SET'?" "y"; then
                print_error "Please run these gcloud commands in your terminal and then re-run this script option."
                print_warning "Aborting Vertex AI configuration for now."
                continue 
            fi
            
            current_vertex_location=$(get_sgptrc_value "VERTEXAI_LOCATION")
            script_default_location="us-central1"
            prompt_default_location="${current_vertex_location:-$script_default_location}"
            read -r "location_val_vertex?Enter your Vertex AI Location (e.g., us-central1) [$prompt_default_location]: "
            VERTEXAI_LOCATION_TO_SET="${location_val_vertex:-$prompt_default_location}"

            # Determine the default model to suggest for Vertex AI configuration
            current_model=$(get_sgptrc_value "DEFAULT_MODEL")
            local vertex_specific_fallback_default="vertex_ai/gemini-2.5-pro-preview-05-06" # A sensible default for Vertex
            local prompt_default_model_for_vertex_selection="$vertex_specific_fallback_default" # Start with the fallback

            if [[ -n "$current_model" ]]; then
                # If current DEFAULT_MODEL is already a Vertex model, use it as the preferred default
                if [[ "$current_model" == "vertex_ai/"* ]] || [[ "$current_model" == "google/"* ]]; then
                    prompt_default_model_for_vertex_selection="$current_model"
                fi
            fi
            # This prompt_default_model_for_vertex_selection will be used in subsequent read prompts
            # for model selection or manual input.

            # Attempt to get suggested models using gcloud first
            local -a suggested_models_array=()
            print_info "Attempting to fetch available Google published models via validation script..."
            
            local validate_script_path
            local script_dir_for_val
            script_dir_for_val="$(cd "$(dirname "$0")" && pwd)" # Directory of sgpt_setup.zsh
            validate_script_path="$script_dir_for_val/validate_vertexai_models.zsh"

            if [[ ! -f "$validate_script_path" ]]; then
                print_error "Validation script not found at $validate_script_path. Skipping gcloud validation."
            else
                # Make sure it's executable
                chmod +x "$validate_script_path"
                
                local validation_output
                local validation_exit_code
                
                # Call the validation script with project and region, capturing its stdout
                # Errors from the validation script (gcloud errors) will go to its stderr
                print_info "Running validation script: $validate_script_path \"$GOOGLE_CLOUD_PROJECT_TO_SET\" \"$VERTEXAI_LOCATION_TO_SET\""
                validation_output=$("$validate_script_path" "$GOOGLE_CLOUD_PROJECT_TO_SET" "$VERTEXAI_LOCATION_TO_SET")
                validation_exit_code=$?

                if [[ $validation_exit_code -eq 0 ]] && [[ -n "$validation_output" ]]; then
                    print_success "Validation script successful. Processing models..."
                    local -a raw_validated_models=("${(@f)validation_output}") # Split by newline
                    
                    if [[ ${#raw_validated_models[@]} -gt 0 ]]; then
                        for id in "${raw_validated_models[@]}"; do
                            # The validation script should already output short IDs.
                            # We add the prefixes sgpt expects.
                            suggested_models_array+=("google/$id")
                            suggested_models_array+=("vertex_ai/$id")
                        done
                        suggested_models_array=(${(u o)suggested_models_array}) # Unique and sort
                        print_success "Found ${#suggested_models_array[@]} potential model entries from validation script."
                    else
                        print_warning "Validation script ran but returned no model IDs."
                    fi
                else
                    print_warning "Validation script failed (exit code $validation_exit_code) or returned no model IDs."
                    print_warning "Check output above from the validation script for gcloud errors (if any)."
                    # No specific error parsing here, as validate_vertexai_models.zsh handles detailed gcloud error printing to its stderr.
                fi
            fi

            # Fallback to sgpt --get-suggested-vertex-models if gcloud failed or found no models
            if [[ ${#suggested_models_array[@]} -eq 0 ]]; then
                print_info "Falling back to fetching suggested models from sgpt (LiteLLM's list)..."
                local sgpt_output_capture
                local sgpt_exit_code=1 # Default to error
                local sgpt_command_to_run=""

                local script_dir
                script_dir="$(cd "$(dirname "$0")" && pwd)"
                local project_root_dir
                project_root_dir="$(cd "$script_dir/.." && pwd)"
                local sgpt_app_py_path="$project_root_dir/sgpt/app.py"

                if command -v python3 &>/dev/null; then
                    if [[ -f "$sgpt_app_py_path" ]]; then
                        sgpt_command_to_run="python3 $sgpt_app_py_path --get-suggested-vertex-models"
                        print_info "Will attempt to use direct script execution: $sgpt_command_to_run"
                    else
                        print_warning "sgpt/app.py not found at $sgpt_app_py_path. Falling back to module/path execution."
                        sgpt_command_to_run="python3 -m sgpt --get-suggested-vertex-models"
                    fi
                elif command -v sgpt &>/dev/null; then
                    sgpt_command_to_run="sgpt --get-suggested-vertex-models"
                else
                    print_warning "Neither 'python3' nor 'sgpt' command found for fallback. Cannot fetch models."
                fi

                if [[ -n "$sgpt_command_to_run" ]]; then
                    print_info "Attempting to run fallback: $sgpt_command_to_run"
                    sgpt_output_capture=$(eval $sgpt_command_to_run 2>&1)
                    sgpt_exit_code=$?
                    print_info "Fallback sgpt command finished with exit code: $sgpt_exit_code"
                fi
                
                local sgpt_suggested_models_str=""
                if [[ $sgpt_exit_code -eq 0 ]] && [[ -n "$sgpt_output_capture" ]]; then
                    # Check for common error patterns even with exit code 0
                    if [[ "$sgpt_output_capture" == *"Traceback"* ]] || \
                       [[ "$sgpt_output_capture" == *"Error:"* ]] || \
                       [[ "$sgpt_output_capture" == *"Exception:"* ]] || \
                       [[ "$sgpt_output_capture" == *"ModuleNotFoundError"* ]]; then
                        
                        # print_warning "DEBUG: Fallback sgpt command (exit 0) output indicates an error."
                        if [[ "$sgpt_output_capture" == *"ModuleNotFoundError"* ]]; then
                            # print_warning "DEBUG: A 'ModuleNotFoundError' was detected. This likely means Python dependencies (e.g., typer, openai, litellm) are not installed in the environment used by 'python3'."
                            # print_warning "DEBUG: Try installing dependencies, e.g., 'pip install .[litellm]' or 'pip install -r requirements.txt' (if available) from the project root."
                        fi
                        # print_warning "DEBUG: Full output from fallback sgpt command:"
                        print "$sgpt_output_capture"
                        # Ensure sgpt_suggested_models_str remains empty to trigger manual input
                        sgpt_suggested_models_str=""
                    else
                        sgpt_suggested_models_str="$sgpt_output_capture"
                    fi
                elif [[ -n "$sgpt_output_capture" ]]; then # Non-zero exit code, and there was output
                    # print_warning "DEBUG: Fallback sgpt command failed (exit code $sgpt_exit_code)."
                    if [[ "$sgpt_output_capture" == *"ModuleNotFoundError"* ]]; then
                        # print_warning "DEBUG: A 'ModuleNotFoundError' was detected. This likely means Python dependencies (e.g., typer, openai, litellm) are not installed in the environment used by 'python3'."
                        # print_warning "DEBUG: Try installing dependencies, e.g., 'pip install .[litellm]' or 'pip install -r requirements.txt' (if available) from the project root."
                    fi
                    # print_warning "DEBUG: Full output from fallback sgpt command:"
                    print "$sgpt_output_capture"
                # else: command failed and produced no output, initial warning about this is sufficient.
                fi

                if [[ -n "$sgpt_suggested_models_str" ]]; then
                    local temp_array_sgpt
                    temp_array_sgpt=("${(@f)sgpt_suggested_models_str}")
                    for line in "${temp_array_sgpt[@]}"; do
                        local line_trimmed_sgpt=$(echo "$line" | awk '{$1=$1};1')
                        if [[ -n "$line_trimmed_sgpt" ]] && [[ "$line_trimmed_sgpt" != *"Traceback"* ]] && [[ "$line_trimmed_sgpt" != *"Error"* ]] && [[ "$line_trimmed_sgpt" != *"Exception"* ]]; then
                            suggested_models_array+=("$line_trimmed_sgpt")
                        fi
                    done
                fi
            fi # End of fallback to sgpt command

            DEFAULT_MODEL_VERTEX=""
            if [[ ${#suggested_models_array[@]} -gt 0 ]]; then
                print_info "\nPlease choose a default Vertex AI model or enter a custom one:"
                local i=1
                while [[ $i -le ${#suggested_models_array[@]} ]]; do
                    print_info "  $i) ${suggested_models_array[$i]}"
                    ((i++))
                done
                print_info "  c) Enter a custom model name"

                local model_choice
                local valid_choice=false
                while ! $valid_choice; do
                    read -r "model_choice?Enter your choice (1-${#suggested_models_array[@]}, or c) [$prompt_default_model_for_vertex_selection if custom/default]: "
                    if [[ "$model_choice" =~ ^[0-9]+$ ]] && [[ "$model_choice" -ge 1 ]] && [[ "$model_choice" -le ${#suggested_models_array[@]} ]]; then
                        DEFAULT_MODEL_VERTEX="${suggested_models_array[$model_choice]}"
                        valid_choice=true
                    elif [[ "$model_choice" == "c" ]] || [[ "$model_choice" == "C" ]]; then
                        read -r "custom_model_val?Enter custom Vertex AI model name [$prompt_default_model_for_vertex_selection]: "
                        DEFAULT_MODEL_VERTEX="${custom_model_val:-$prompt_default_model_for_vertex_selection}"
                        if [[ -z "$DEFAULT_MODEL_VERTEX" ]]; then
                            print_warning "Custom model name cannot be empty. Using fallback default."
                            DEFAULT_MODEL_VERTEX="$prompt_default_model_for_vertex_selection"
                        fi
                        valid_choice=true
                    elif [[ -z "$model_choice" ]] && [[ -n "$prompt_default_model" ]]; then
                        # If user just hits enter and there's a current/fallback default
                        DEFAULT_MODEL_VERTEX="$prompt_default_model"
                        print_info "Using default: $DEFAULT_MODEL_VERTEX"
                        valid_choice=true
                    else
                        print_warning "Invalid choice. Please select a number from the list or 'c'."
                    fi
                done
            else
                # This block is reached if suggested_models_array is empty after processing
                if [[ $sgpt_exit_code -ne 0 ]] || [[ -z "$sgpt_output_capture" && -n "$sgpt_command_to_run" ]]; then
                    # If command failed or produced no output, this warning is appropriate
                    print_warning "Could not fetch suggested models (command failed or produced no valid output). Please enter manually."
                elif [[ -n "$sgpt_command_to_run" ]]; then
                     # If command ran but array is still empty (e.g. filtered out all lines)
                    print_warning "Fetched model list was empty or invalid after processing. Please enter manually."
                fi
                # Fallback to manual input
                read -r "default_model_val_vertex?Enter default Vertex AI model (e.g., $vertex_specific_fallback_default) [$prompt_default_model_for_vertex_selection]: "
                DEFAULT_MODEL_VERTEX="${default_model_val_vertex:-$prompt_default_model_for_vertex_selection}"
            fi
            
            if [[ -z "$DEFAULT_MODEL_VERTEX" ]]; then
                 print_error "Vertex AI model name cannot be empty. Using script fallback: $vertex_specific_fallback_default"
                 DEFAULT_MODEL_VERTEX="$vertex_specific_fallback_default"
            fi

            update_sgptrc_value "OPENAI_API_KEY" "\"DISABLED_SGPT_SETUP_USING_VERTEX_AI\""
            update_sgptrc_value "GOOGLE_API_KEY" "\"DISABLED_SGPT_SETUP_USING_VERTEX_AI\""
            update_sgptrc_value "DEFAULT_MODEL" "$DEFAULT_MODEL_VERTEX"
            update_sgptrc_value "GOOGLE_CLOUD_PROJECT" "$GOOGLE_CLOUD_PROJECT_TO_SET"
            update_sgptrc_value "VERTEXAI_LOCATION" "$VERTEXAI_LOCATION_TO_SET"
            update_sgptrc_value "USE_LITELLM" "true" 

            print_success "\nSGPT config file ($SGPT_CONFIG_FILE) updated for Vertex AI."
            print_info "Primary authentication will be via gcloud Application Default Credentials."
            print_info "Ensure GOOGLE_APPLICATION_CREDENTIALS env var is NOT set if using user ADC."
            
            if [[ -n "$GOOGLE_CLOUD_PROJECT_TO_SET" ]]; then
                GCP_PROJECT_EXPORT_LINE="export GOOGLE_CLOUD_PROJECT=\"$GOOGLE_CLOUD_PROJECT_TO_SET\" $SCRIPT_MARKER"
                add_export_to_shell_config "$GCP_PROJECT_EXPORT_LINE" "GOOGLE_CLOUD_PROJECT"
            fi
            if [[ -n "$VERTEXAI_LOCATION_TO_SET" ]]; then
                GCP_LOCATION_EXPORT_LINE="export VERTEXAI_LOCATION=\"$VERTEXAI_LOCATION_TO_SET\" $SCRIPT_MARKER"
                add_export_to_shell_config "$GCP_LOCATION_EXPORT_LINE" "VERTEXAI_LOCATION"
            fi
            if ask_yes_no "To ensure Vertex AI ADC is used, comment out OPENAI_API_KEY and GOOGLE_API_KEY from $PREFERRED_SHELL_CONFIG_FILE if present?"; then
                if [[ -n "$PREFERRED_SHELL_CONFIG_FILE" ]] && [[ -f "$PREFERRED_SHELL_CONFIG_FILE" ]]; then
                    local sed_temp_file="${PREFERRED_SHELL_CONFIG_FILE}.sedtmp"
                    cp "$PREFERRED_SHELL_CONFIG_FILE" "$sed_temp_file"
                    sed "s|^export OPENAI_API_KEY=.*$SCRIPT_MARKER$|# export OPENAI_API_KEY=... $SCRIPT_MARKER # Commented out for Vertex AI|" "$sed_temp_file" > "$PREFERRED_SHELL_CONFIG_FILE"
                    cp "$PREFERRED_SHELL_CONFIG_FILE" "$sed_temp_file" 
                    sed "s|^export GOOGLE_API_KEY=.*$SCRIPT_MARKER$|# export GOOGLE_API_KEY=... $SCRIPT_MARKER # Commented out for Vertex AI|" "$sed_temp_file" > "$PREFERRED_SHELL_CONFIG_FILE"
                    rm -f "$sed_temp_file"
                    print_info "Attempted to comment out other API key exports in $PREFERRED_SHELL_CONFIG_FILE."
                fi
            fi
            main_menu_loop_active=false 
            ;;
        4) # Exit
            print_info "Exiting configuration."
            main_menu_loop_active=false 
            exit 0
            ;;
        *) 
            print_error "Invalid option ($user_choice_num) processed by case. This should not happen." 
            ;;
    esac
done

print_info "\n--- Configuration Script Finished ---"
if [[ "$user_choice_num" -ne 4 ]]; then 
    print_info "Next steps:"
    print_info "1. If your shell configuration file ($PREFERRED_SHELL_CONFIG_FILE) was modified,"
    print_info "   ensure you run 'source $PREFERRED_SHELL_CONFIG_FILE' or open a new terminal."
    print_info "2. For Vertex AI, if you haven't already, complete the 'gcloud auth' steps in another terminal if prompted."
    print_info "3. Test SGPT with a simple prompt: sgpt \"Hello world\""
    print_info "   To use a specific model: sgpt --model <your_model_name> \"Hello world\""
fi
exit 0