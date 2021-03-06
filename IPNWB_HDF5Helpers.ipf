#pragma TextEncoding = "UTF-8"
#pragma rtGlobals=3		// Use modern global access method and strict wave access.
#pragma rtFunctionErrors=1
#pragma IndependentModule=IPNWB
#pragma version=0.18

// This file is part of the `IPNWB` project and licensed under BSD-3-Clause.

static Constant H5_ATTRIBUTE_SIZE_LIMIT = 60e3
static Constant H5_CHUNK_SIZE           = 8192 // 2^13, determined by trial-and-error

/// @file IPNWB_HDF5Helpers.ipf
/// @brief __H5__ Wrapper functions for convenient use of the HDF5 operations

/// @brief Write a string or text wave into a HDF5 dataset
///
/// @param locationID                                  HDF5 identifier, can be a file or group
/// @param name                                        Name of the HDF5 dataset
/// @param str                                         Contents to write into the dataset
/// @param wvText                                      Contents to write into the dataset
/// @param overwrite [optional, defaults to false]     Should existing datasets be overwritten
/// @param chunkedLayout [optional, defaults to false] Use chunked layout with compression and shuffling
/// @param skipIfExists [optional, defaults to false]  Do nothing if the dataset already exists
/// @param writeIgorAttr [optional, defaults to false] Add Igor specific attributes to the dataset, see the `/IGOR` flag of `HDF5SaveData`
///
/// Only one of `str` or `wvText` can be given.
Function H5_WriteTextDataset(locationID, name, [str, wvText, overwrite, chunkedLayout, skipIfExists, writeIgorAttr])
	variable locationID
	string name, str
	Wave/Z/T wvText
	variable overwrite, chunkedLayout, skipIfExists, writeIgorAttr

	overwrite     = ParamIsDefault(overwrite)     ? 0 : !!overwrite
	chunkedLayout = ParamIsDefault(chunkedLayout) ? 0 : !!chunkedLayout
	skipIfExists  = ParamIsDefault(skipIfExists)  ? 0 : !!skipIfExists
	writeIgorAttr = ParamIsDefault(writeIgorAttr) ? 0 : !!writeIgorAttr

	ASSERT(ParamIsDefault(str) + ParamIsDefault(wvText) == 1, "Need exactly one of str or wvText")

	if(!ParamIsDefault(str))
		Make/FREE/T/N=1 wvText = str
	endif

	H5_WriteDatasetLowLevel(locationID, name, wvText, overwrite, chunkedLayout, skipIfExists, writeIgorAttr)
End

/// @brief Write a variable or text wave into a HDF5 dataset
///
/// @param locationID                                  HDF5 identifier, can be a file or group
/// @param name                                        Name of the HDF5 dataset
/// @param var                                         Contents to write into the dataset
/// @param varType                                     Type of the data, must be given if `var` is supplied. See @ref IgorTypes
/// @param wv                                          Contents to write into the dataset
/// @param overwrite [optional, defaults to false]     Should existing datasets be overwritten
/// @param chunkedLayout [optional, defaults to false] Use chunked layout with compression and shuffling
/// @param skipIfExists [optional, defaults to false]  Do nothing if the dataset already exists
/// @param writeIgorAttr [optional, defaults to false] Add Igor specific attributes to the dataset, see the `/IGOR` flag of `HDF5SaveData`
///
/// Only one of `var` or `wv` can be given.
Function H5_WriteDataset(locationID, name, [var, varType, wv, overwrite, chunkedLayout, skipIfExists, writeIgorAttr])
	variable locationID
	string name
	variable var, varType
	Wave/Z wv
	variable overwrite, chunkedLayout, skipIfExists, writeIgorAttr

	overwrite     = ParamIsDefault(overwrite)     ? 0 : !!overwrite
	chunkedLayout = ParamIsDefault(chunkedLayout) ? 0 : !!chunkedLayout
	skipIfExists  = ParamIsDefault(skipIfExists)  ? 0 : !!skipIfExists
	writeIgorAttr = ParamIsDefault(writeIgorAttr) ? 0 : !!writeIgorAttr

	ASSERT(ParamIsDefault(var) + ParamIsDefault(wv) == 1, "Need exactly one of var or wv")

	if(!ParamIsDefault(var))
		ASSERT(!ParamIsDefault(varType), "var needs varType")
		Make/FREE/Y=(varType)/N=1 wv = var
	endif

	H5_WriteDatasetLowLevel(locationID, name, wv, overwrite, chunkedLayout, skipIfExists, writeIgorAttr)
End

/// @brief Return a wave for the valid chunk sizes of each dimension.
static Function/Wave H5_GetChunkSizes(wv)
	WAVE wv

	MAKE/FREE/N=(WaveDims(wv))/I/U chunkSizes = (DimSize(wv, p) > H5_CHUNK_SIZE ? H5_CHUNK_SIZE : 32)

	return chunkSizes
End

/// @see H5_WriteTextDataset or H5_WriteDataset
static Function H5_WriteDatasetLowLevel(locationID, name, wv, overwrite, chunkedLayout, skipIfExists, writeIgorAttr)
	variable locationID
	string name
	Wave wv
	variable overwrite, chunkedLayout, skipIfExists, writeIgorAttr

	variable numDims, attrFlag

	ASSERT(H5_IsValidIdentifier(GetFile(name, sep="/")), "name of saved dataset is not valid HDF5 format")

	numDims = WaveDims(wv)

	if(skipIfExists && H5_DatasetExists(locationID, name))
		return NaN
	endif

	attrFlag = writeIgorAttr ? -1 : 0

	if(chunkedLayout)
		WAVE chunkSizes = H5_GetChunkSizes(wv)
	endif

	if(attrFlag & 16) // saving wave note as attribute
		if(strlen(note(wv)) >= H5_ATTRIBUTE_SIZE_LIMIT)
			// by default HDF5 attributes are stored in the object header and thus attributes are limited to 64k size
			printf "The wave note of the wave \"%s\" (stored name: \"%s\") will be shortend to enable HDF5/NWB storage\r", NameOfWave(wv), name
			ControlWindowToFront()

			Duplicate/FREE wv, wvCopy
			Note/K wvCopy, note(wv)[0, H5_ATTRIBUTE_SIZE_LIMIT]
			WAVE wv = wvCopy
		endif
	endif

	if(overwrite)
		if(chunkedLayout)
			if(numDims == 1)
				HDF5SaveData/IGOR=(attrFlag)/GZIP={3, 1}/LAYO={2, chunkSizes[ROWS]}/MAXD={-1}/O/Z wv, locationID, name
			elseif(numDims == 2)
				HDF5SaveData/IGOR=(attrFlag)/GZIP={3, 1}/LAYO={2, chunkSizes[ROWS], chunkSizes[COLS]}/MAXD={-1, -1}/O/Z wv, locationID, name
			elseif(numDims == 3)
				HDF5SaveData/IGOR=(attrFlag)/GZIP={3, 1}/LAYO={2, chunkSizes[ROWS], chunkSizes[COLS], chunkSizes[LAYERS]}/MAXD={-1, -1, -1}/O/Z wv, locationID, name
			elseif(numDims == 4)
				HDF5SaveData/IGOR=(attrFlag)/GZIP={3, 1}/LAYO={2, chunkSizes[ROWS], chunkSizes[COLS], chunkSizes[LAYERS], chunkSizes[CHUNKS]}/MAXD={-1, -1, -1, -1}/O/Z wv, locationID, name
			else
				ASSERT(0, "unhandled numDims")
			endif
		else
			HDF5SaveData/IGOR=(attrFlag)/O/Z wv, locationID, name
		endif
	else
		if(chunkedLayout)
			if(numDims == 1)
				HDF5SaveData/IGOR=(attrFlag)/GZIP={3, 1}/LAYO={2, chunkSizes[ROWS]}/MAXD={-1}/Z wv, locationID, name
			elseif(numDims == 2)
				HDF5SaveData/IGOR=(attrFlag)/GZIP={3, 1}/LAYO={2, chunkSizes[ROWS], chunkSizes[COLS]}/MAXD={-1, -1}/Z wv, locationID, name
			elseif(numDims == 3)
				HDF5SaveData/IGOR=(attrFlag)/GZIP={3, 1}/LAYO={2, chunkSizes[ROWS], chunkSizes[COLS], chunkSizes[LAYERS]}/MAXD={-1, -1, -1}/Z wv, locationID, name
			elseif(numDims == 4)
				HDF5SaveData/IGOR=(attrFlag)/GZIP={3, 1}/LAYO={2, chunkSizes[ROWS], chunkSizes[COLS], chunkSizes[LAYERS], chunkSizes[CHUNKS]}/MAXD={-1, -1, -1, -1}/Z wv, locationID, name
			else
				ASSERT(0, "unhandled numDims")
			endif
		else
			HDF5SaveData/IGOR=(attrFlag)/Z wv, locationID, name
		endif
	endif

	if(V_flag)
		HDf5DumpErrors/CLR=1
		HDF5DumpState
		ASSERT(0, "Could not store HDF5 dataset to file")
	endif
End

/// @brief Attach a text attribute to the given location
///
/// @param locationID                              HDF5 identifier, can be a file, group or dataset
/// @param attrName                                Name of the attribute
/// @param path                                    Additional path on top of `locationID` which identifies the object onto which the
///                                                attribute should be attached.
/// @param list                                    Contents to write into the attribute, list will be always written as 1D-array
/// @param str                                     Contents to write into the attribute
/// @param overwrite [optional, defaults to false] Should existing attributes be overwritten
///
/// Only one of `str ` or `list` can be given.
Function H5_WriteTextAttribute(locationID, attrName, path, [list, str, overwrite])
	variable locationID
	string attrName, path
	string list, str
	variable overwrite

	variable forceSimpleDataSpace

	ASSERT(ParamIsDefault(str) + ParamIsDefault(list) == 1, "Need exactly one of str or list")

	if(!ParamIsDefault(str))
		Make/FREE/T/N=(1) data = str
	elseif(!ParamIsDefault(list))
		Make/FREE/T/N=(ItemsInList(list)) data = StringFromList(p, list)
		forceSimpleDataSpace = 1
	endif

	overwrite = ParamIsDefault(overwrite) ? 0 : !!overwrite

	if(overwrite)
		HDF5SaveData/A={attrName, forceSimpleDataSpace}/IGOR=0/O/Z data, locationID, path
	else
		HDF5SaveData/A={attrName, forceSimpleDataSpace}/IGOR=0/Z data, locationID, path
	endif

	if(V_flag)
		HDf5DumpErrors/CLR=1
		HDF5DumpState
		ASSERT(0, "Could not write HDF5 attribute to file")
	endif
End

/// @brief Attach a numerical attribute to the given location
///
/// @param locationID                              HDF5 identifier, can be a file, group or dataset
/// @param attrName                                Name of the attribute
/// @param path                                    Additional path on top of `locationID` which identifies
///                                                the object onto which the attribute should be attached.
/// @param var                                     Contents to write into the attribute
/// @param varType                                 Type of the attribute, see @ref IgorTypes
/// @param overwrite [optional, defaults to false] Should existing attributes be overwritten
///
/// Only one of `str `, `wvText` or `list` can be given.
Function H5_WriteAttribute(locationID, attrName, path, var, varType, [overwrite])
	variable locationID
	string attrName, path
	variable var, varType
	variable overwrite

	Make/FREE/Y=(varType)/N=1 data = var

	overwrite = ParamIsDefault(overwrite) ? 0 : !!overwrite

	if(overwrite)
		HDF5SaveData/A=attrName/IGOR=0/O/Z data, locationID, path
	else
		HDF5SaveData/A=attrName/IGOR=0/Z data, locationID, path
	endif

	if(V_flag)
		HDf5DumpErrors/CLR=1
		HDF5DumpState
		ASSERT(0, "Could not write HDF5 attribute to file")
	endif
End

/// @brief Open HDF5 file and return ID
///
/// @param discLocation  full path to nwb file
/// @param write         open file for writing. default is readonly.
/// @return              ID for referencing open hdf5 file
Function H5_OpenFile(discLocation, [write])
	string discLocation
	variable write
	if(ParamIsDefault(write))
		write = 0
	endif

	variable fileID

	GetFileFolderInfo/Q/Z discLocation
	ASSERT(!V_Flag, "The given file does not exist.")

	if(write)
		HDF5OpenFile/Z fileID as discLocation
	else
		HDF5OpenFile/Z/R fileID as discLocation
	endif
	if(V_flag)
		HDf5DumpErrors/CLR=1
		HDF5DumpState
		ASSERT(0, "Could not open HDF5 file.")
	endif

	return fileID
End

/// @brief Close HDF5 file
///
/// @param fileID  ID of open hdf5 file
/// @return        open state as true/false
Function H5_CloseFile(fileID)
	variable fileID

	if(H5_IsFileOpen(fileID))
		// try to close the file (once)
		HDF5CloseFile/Z fileID
		return H5_IsFileOpen(fileID)
	endif

	return 0
End

/// @brief Return 1 if the given HDF5 file is already open, 0 otherwise.
///
/// @param fileID HDF5 locationID from `HDF5OpenFile`.
Function H5_IsFileOpen(fileID)
	variable fileID

	// group "/" does exist, therefore the fileID refers to an open file
	return H5_GroupExists(fileID, "/")
End

/// Taken from HDF5 Browser.ipf
///
/// Included here for convenience.
/// @{
static Constant kHDF5DataInfoVersion = 1000		// 1000 means 1.000.
static Constant H5S_MAX_RANK = 32

threadsafe static Function InitHDF5DataInfo(di)				// Sets input fields.
	STRUCT HDF5DataInfo &di

	// HDF5XOP uses these fields to make sure the structure passed in to it is compatible.
	di.version = kHDF5DataInfoVersion
	di.structName = "HDF5DataInfo"
End

static Structure HDF5DataInfo					// Use with HDF5DatasetInfo and HDF5AttributeInfo functions
	// Input fields (inputs to HDF5 XOP)
	uint32 version							// Must be set to kHDF5DataInfoVersion
	char structName[16]						// Must be "HDF5DataInfo".

	// Output fields (outputs from HDF5 XOP)
	double datatype_class;				// e.g., H5T_INTEGER, H5T_FLOAT.
	char datatype_class_str[32];			// String with class spelled out. e.g., "H5T_INTEGER", "H5T_FLOAT".
	double datatype_size;					// Size in bytes of one element.
	double datatype_sign;					// H5T_SGN_NONE (unsigned), H5T_SGN_2 (signed), H5T_SGN_ERROR (this type does not have a sign, i.e., it is not an integer type).
	double datatype_order;				// H5T_ORDER_LE, H5T_ORDER_BE, H5T_ORDER_VAX
	char datatype_str[64];				// Human-readable string, e.g., "16-bit unsigned integer"
	double dataspace_type;				// H5S_NO_CLASS, H5S_SCALAR, H5S_SIMPLE
	double ndims;							// Zero for H5S_SCALAR. Number of dimensions in the dataset for H5S_SIMPLE.
	double dims[H5S_MAX_RANK];			// Size of each dimension.
	double maxdims[H5S_MAX_RANK];		// Maximum size of each dimension.
EndStructure
/// @}

/// @brief Return 1 if the given HDF5 dataset exists, 0 otherwise.
///
/// @param[in] locationID           HDF5 identifier, can be a file or group
/// @param[in] name                 Additional path on top of `locationID` which identifies
///                                 the dataset
Function H5_DatasetExists(locationID, name)
	variable locationID
	string name

	STRUCT HDF5DataInfo di
	InitHDF5DataInfo(di)

	return !HDF5DatasetInfo(locationID, name, 2^0, di)
End

/// @brief Load a specified dataset as wave
///
/// @param[in] locationID HDF5 identifier, can be a file or group
/// @param[in] name       path on top of `locationID` which identifies the dataset
///
/// @return               reference to wave containing loaded data
Function/WAVE H5_LoadDataset(locationID, name)
	variable locationID
	string name

	if(!H5_DatasetExists(locationID, name))
		return $""
	endif

	DFREF saveDFR = GetDataFolderDFR()
	DFREF dfr = NewFreeDataFolder()

	SetDataFolder dfr
	HDF5LoadData/Q/IGOR=(-1) locationID, name
	SetDataFolder saveDFR

	if(V_flag)
		HDf5DumpErrors/CLR=1
		HDF5DumpState
		ASSERT(0, "Could not read HDF5 dataset " + name)
	endif

	ASSERT(ItemsInList(S_waveNames) == 1, "unspecified data format")

	WAVE/Z wv = dfr:$StringFromList(0, S_waveNames)
	ASSERT(WaveExists(wv), "loaded wave not found")

	return wv
End

/// @brief Check if a given attribute exists
///
/// @param[in]  locationID            HDF5 identifier, can be a file or group
/// @param[in]  path                  Additional path on top of `locationID` which identifies
///                                   the group or dataset
/// @param[in]  attribute             Name of the attribute
/// @param[out] objectType [optional] Return the type of the element to which the
///                                   attribute is attached to. Can be used for subsequent HDF5LoadData calls.
Function H5_AttributeExists(locationID, path, attribute, [objectType])
	variable locationID
	string path, attribute
	variable &objectType

	variable objectTypeVar, datasetExists, groupExists

	STRUCT HDF5DataInfo di
	InitHDF5DataInfo(di)

	datasetExists = H5_DatasetExists(locationID, path)
	groupExists = H5_GroupExists(locationID, path)

	if(datasetExists && groupExists)
		ASSERT(0, "Could not handle attribute when both a group and a dataset exist with the same name.")
	elseif(groupExists)
		objectTypeVar = 1
	elseif(datasetExists)
		objectTypeVar = 2
	endif

	if(!ParamisDefault(objectType))
		objectType = objectTypeVar
	endif

	return !HDF5AttributeInfo(locationID, path, objectTypeVar, attribute, 2^0, di)
End

/// @brief Load the given attribute and return its contents
///
/// @param[in]  locationID HDF5 identifier, can be a file or group
/// @param[in]  path       Additional path on top of `locationID` which identifies
///                        the group or dataset
/// @param[in]  attribute  Name of the attribute to load
Function/WAVE H5_LoadAttribute(locationID, path, attribute)
	variable locationID
	string path, attribute

	variable objectType

	if(!H5_AttributeExists(locationID, path, attribute, objectType = objectType))
		return $""
	endif

	DFREF saveDFR = GetDataFolderDFR()
	DFREF dfr = NewFreeDataFolder()

	SetDataFolder dfr
	HDF5LoadData/A=(attribute)/TYPE=(objectType)/Q/Z locationID, path
	SetDataFolder saveDFR

	if(V_Flag)
		HDf5DumpErrors/CLR=1
		HDF5DumpState
		ASSERT(0, "Could not load the HDF5 attribute '" + attribute + "' from '" + path + "'\rError No: " + num2str(V_Flag))
	endif

	ASSERT(ItemsInList(S_waveNames) == 1, "unspecified data format")

	WAVE/Z wv = dfr:$StringFromList(0, S_waveNames)
	ASSERT(WaveExists(wv), "loaded wave not found")

	return wv
End

/// @brief Return 1 if the given HDF5 group exists, 0 otherwise.
///
/// @param[in] locationID           HDF5 identifier, can be a file or group
/// @param[in] path                 Additional path on top of `locationID` which identifies
///                                 the group
/// @param[out] groupID [optional]  Allows to return the locationID of the group, zero in case
///                                 the group does not exist. If this parameter is not provided,
///                                 the group is closed before the function returns.
Function H5_GroupExists(locationID, path, [groupID])
	variable locationID
	string path
	variable &groupID

	variable id, success

	HDF5OpenGroup/Z locationID, path, id
	success = !V_Flag

	if(ParamIsDefault(groupID))
		if(success)
			HDF5CloseGroup id
		endif
	else
		groupID = id
	endif

	return success
End

/// @brief Create all groups along the given path
///
/// @param[in] locationID          HDF5 identifier, can be a file or group
/// @param[in] fullPath            Additional path on top of `locationID` which identifies
///                                the group
/// @param[out] groupID [optional] Allows to return the locationID of the group, zero in case
///                                the group could not be created. If this parameter is not
///                                provided, the group is closed before the function returns.
Function H5_CreateGroupsRecursively(locationID, fullPath, [groupID])
	variable locationID
	string fullPath
	variable &groupID

	variable id, i, numElements, start
	string path, group

	if(!H5_GroupExists(locationID, fullPath, groupID=id))
		numElements = ItemsInList(fullPath, "/")

		if(!cmpstr(fullPath[0], "/"))
			start = 1
			path   = "/"
		else
			start = 0
			path   = ""
		endif

		for(i = start; i < numElements; i += 1)
			group = StringFromList(i, fullPath, "/")
			path += group

			ASSERT(H5_IsValidIdentifier(group), "invalid HDF5 group name")

			HDF5CreateGroup/Z locationID, path, id
			if(V_flag)
				HDf5DumpErrors/CLR=1
				HDF5DumpState
				ASSERT(0, "Could not create HDF5 group")
			endif

			if(i != numElements - 1)
				HDF5CloseGroup/Z id
			endif

			path += "/"
		endfor
	endif

	if(ParamIsDefault(groupID))
		HDF5CloseGroup id
	else
		groupID = id
	endif
End

/// @brief Return true if `name` is a valid hdf5 identifier
///
/// This is more restrictive than the actual HDF5 library checks.
/// See the BNF Grammar [here](https://www.hdfgroup.org/HDF5/doc/UG/HDF5_Users_Guide-Responsive%20HTML5/index.html#t=HDF5_Users_Guide%2FGroups%2FHDF5_Groups.htm%3Frhtocid%3Dtoc4.0_1%23TOC_4_1_Introductionbc-1).
Function H5_IsValidIdentifier(name)
	string name

	return GrepString(name, "^[A-Za-z0-9_ -]+$")
End

/// @brief List all datasets at path (non-recursively)
///
/// @param[in] locationID          HDF5 identifier, can be a file or group
/// @param[in] path                Additional path on top of `locationID` which identifies
///                                the group
Function/S H5_ListGroupMembers(locationID, path)
	variable locationID
	string path

	ASSERT(H5_GroupExists(locationID, path), path + " not in HDF5 file")

	HDF5ListGroup/Z locationID, path
	if(V_flag)
		HDf5DumpErrors/CLR=1
		HDF5DumpState
		ASSERT(0, "HDF5ListGroup returned error " + num2str(V_flag))
	endif

	return S_HDF5ListGroup
End

/// @brief List all groups inside a group (non-recursively)
///
/// @param[in]  fileID        HDF5 file identifier
/// @param[in]  path          Full path to the group inside fileID
Function/S H5_ListGroups(fileID, path)
	variable fileID
	string path

	ASSERT(H5_GroupExists(fileID, path), path + " not in HDF5 file")

	HDF5ListGroup/TYPE=1/Z fileID, path
	if(V_flag)
		HDf5DumpErrors/CLR=1
		HDF5DumpState
		ASSERT(0, "HDF5ListGroup returned error " + num2str(V_flag))
	endif

	return S_HDF5ListGroup
End

/// @brief Open the group reachable via `locationID` and `path` and return its ID
///
/// @param locationID  HDF5 file identifier
/// @param path        Full path to the group inside locationID
Function H5_OpenGroup(locationID, path)
	variable locationID
	string path

	variable id

	ASSERT(H5_GroupExists(locationID, path, groupID = id), path + " not in HDF5 file")

	return id
End

#if (IgorVersion() >= 8.00)

/// @brief Flush the file contents to disc
/// @param fileID       HDF5 file identifier
/// @param discLocation unused (for compatibility with the Igor Pro 7 version only)
/// @param write        unused (for compatibility with the Igor Pro 7 version only)
///
/// @return fileID  (for compatibility with the Igor Pro 7 version only)
Function H5_FlushFile(fileID, discLocation, [write])
	variable fileID
	string discLocation
	variable write

	HDF5FlushFile fileID

	return fileID
End

#else

/// @brief Flush the file contents to disc
///
/// Currently uses open/close and thus it is not very fast. This approach results
/// in the fileID being changed!
///
/// @param fileID       HDF5 file identifier
/// @param discLocation Full path to the HDF5 file
/// @param write        [optional, defaults to false] Reopen the file for writing
///
/// @return changed fileID
Function H5_FlushFile(fileID, discLocation, [write])
	variable fileID
	string discLocation
	variable write

	DEBUGPRINT("H5_FlushFile: Flushing!")

	HDF5CloseFile/Z fileID

	if(V_flag)
		DEBUGPRINT("Closing the HDF5 File returned error:", var = V_flag)
		return NaN
	endif

	return H5_OpenFile(discLocation, write = write)
End

#endif
