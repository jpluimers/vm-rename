#!/bin/sh
#
# shell script to rename a virtual machine in ESXi
#set -x

if [ $# -ne 4 ]; then
  echo "Usage: $0 VOLNAME DIRNAME OLDNAME NEWNAME
  
where VOLNAME is the volume name, e.g. datastore1,
      DIRNAME is the the name of the directory of the virtual machine,
      OLDNAME is the name of the files of the virtual machine before the '.',
      NEWNAME is the new name for the directory and the files.
      
examples:

      vm-rename VMs \"(NEW) p56 25 centos6 x8664 c.net\"  p56-25-centos6-x8664-c.net p56-25-centos6-x8664-C.net
      vm-rename.sh NVMe980PRO_1TB/VM X9SRI-3F-W10P-NL-OFFICE X9SRI-3F-W10P-NL X9SRI-3F-W10P-NL-OFFICE
      
If registered before: !!do NOT forget to unregister the VM from the inventory first!!

to get the <vmid> of the old VM, use:

      vim-cmd vmsvc/getallvms

unregister:

      vim-cmd vmsvc/unregister <vmid>

register after rename:

      vim-cmd solo/registervm <path_to_vmx_file>
"
  exit 1
fi
  
VOLNAME="$1"
DIRNAME="$2"
export OLDNAME="$3"
export NEWNAME="$4"
VM_DIRPATH="/vmfs/volumes/$VOLNAME/$DIRNAME"
NW_DIRPATH="/vmfs/volumes/$VOLNAME/$NEWNAME"

echo "VOLNAME=$VOLNAME"
echo "DIRNAME=$DIRNAME"
echo "OLDNAME=$OLDNAME"
echo "NEWNAME=$NEWNAME"
echo "VM_DIRPATH=$VM_DIRPATH"
echo "NW_DIRPATH=$NW_DIRPATH"

if [ ! -d "$VM_DIRPATH" ]; then
  echo "The directory path $VM_DIRPATH is invalid"
  exit 1
fi
  
if [ "$DIRNAME" != "$NEWNAME" ]; then
  if [ -d "$NW_DIRPATH" ]; then
    echo "The new directory path $NW_DIRPATH already exists"
    exit 1
  fi
fi
  
cd "$VM_DIRPATH"

if [ ! -f "$OLDNAME".vmdk ]; then
  echo "$OLDNAME.vmdk not found. Exiting. No harm done yet."
  exit 1
fi

if [ ! -f "$OLDNAME".vmx ]; then
  echo "$OLDNAME.vmx not found. Exiting. No harm done yet."
  exit 1
fi

if [ -f "$OLDNAME".vmx.lck ]; then
  echo "$OLDNAME.vmx.lck found. Is this VM running? Exiting. No harm done yet."
  exit 1
fi

### DONE CHECKING, NOW GET TO WORK

# First rename the vmdk files. We have to use vmkfstools for this
# Use a find trick to handle spaces in names.
#
find . -type f -name "*$OLDNAME*.vmdk" -and -not -name "*-flat.vmdk" -exec sh -c " 
 FILE=\$(echo \"\$0\" | sed \"s/\$OLDNAME/\$NEWNAME/g\"); 
 echo renaming \"\$0\" to \"\$FILE\";
 vmkfstools -E \"\$0\" \"\$FILE\";
" {} \;

# Replace all file references in the .vmx file
#
cp "$OLDNAME".vmx "$OLDNAME".vmx.backup
sed -i "s/$OLDNAME/$NEWNAME/g" "$OLDNAME".vmx
if [ $? -ne 0 ]; then
  echo "ERROR using sed to replace \"$OLDNAME\" with \"$NEWNAME\" in \"$OLDNAME\".vmx. Exiting.."
  echo "The VM may now be left in an inconsistent state, and you may need to fix it manually."
  exit 1
fi
                
# Rename the remaining files. Use `find` trick to handle spaces in names 
#
find . -type f -name "*$OLDNAME*" -and -not -name "*.vmdk" -exec sh -c " 
 FILE=\$(echo \"\$0\" | sed \"s/\$OLDNAME/\$NEWNAME/g\"); 
 echo renaming \"\$0\" to \"\$FILE\";
 mv \"\$0\" \"\$FILE\";
" {} \;

# Finally rename the directory
#
cd ..
if [ "$DIRNAME" != "$NEWNAME" ]; then
  mv "$DIRNAME" "$NEWNAME"
  if [ $? -ne 0 ]; then
    echo "ERROR renaming \"$DIRNAME\" to \"$NEWNAME\". Trying with objtool if DataStore is VSAN..."
    if [ -f /usr/lib/vmware/osfs/bin/objtool ]; then
      # Try to rename folder via objtool - mv cannot be used for folders in vSAN
      /usr/lib/vmware/osfs/bin/objtool setAttr -u $(readlink "$DIRNAME") -n "$NEWNAME"
      if [ $? -ne 0 ]; then
        echo "The VM is now in an inconsistent state, and you need to fix it manually."
        exit 1
      fi
    else
      # mv failed to rename and no objtool found, so bail out:
      echo "The VM is now in an inconsistent state, and you need to fix it manually."
      exit 1
    fi
  fi
fi

echo "All Done. You now need to register $NEWNAME to the inventory using:
      vim-cmd solo/registervm $NW_DIRPATH/$NEWNAME.vmx
You might need to unregister the old VM first using:
      vim-cmd vmsvc/unregister <vmid>
If you need the <vmid>:
      vim-cmd vmsvc/getallvms
"

#EOF
